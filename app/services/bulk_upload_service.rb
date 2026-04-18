require 'csv'

class BulkUploadService
  # import_type: brands, categories, cat_filters, roles, products
  # csv_data: string
  def self.import(import_type, csv_data)
    rows = CSV.parse(csv_data.encode("UTF-8", invalid: :replace, undef: :replace), headers: true)
    successes = []
    errors = []

    rows.each_with_index do |row, idx|
      begin
        case import_type
        when 'brands'
          rec = import_brand(row)
        when 'categories'
          rec = import_category(row)
        when 'cat_filters'
          rec = import_cat_filter(row)
        when 'roles'
          rec = import_role(row)
        when 'products'
          rec = import_product(row)
        else
          raise "Unknown import type"
        end

        if rec.respond_to?(:errors) && rec.errors.any?
          errors << { row: idx + 1, errors: rec.errors.full_messages }
        else
          successes << { row: idx + 1, id: rec.try(:id) }
        end
      rescue => e
        errors << { row: idx + 1, error: e.message }
      end
    end

    { success_count: successes.size, error_count: errors.size, successes: successes, errors: errors }
  end

  def self.import_brand(row)
    name = row['name'].to_s.encode('UTF-8', invalid: :replace, undef: :replace)
    attrs = {
      name: name,
      is_active: parse_bool(row['is_active'])
    }
    Brand.find_or_initialize_by(name: name).tap { |b| b.update(attrs) }
  end

  def self.import_category(row)
    name = row['name'].to_s.encode('UTF-8', invalid: :replace, undef: :replace)
    attrs = {
      name: name,
      is_active: parse_bool(row['is_active'])
    }
    Category.find_or_initialize_by(name: name).tap { |c| c.update(attrs) }
  end

  def self.import_cat_filter(row)
    attrs = {
      name: row['name'],
      key: row['key'] || row['name'].to_s.parameterize.underscore,
      category_id: row['category_id'].present? ? row['category_id'].to_i : nil,
      is_active: parse_bool(row['is_active'])
    }
    CatFilter.find_or_initialize_by(key: attrs[:key]).tap { |f| f.update(attrs) }
  end

  def self.import_role(row)
    attrs = { name: row['name'], is_active: parse_bool(row['is_active']) }
    perms = {}
    if row['module_permissions'].present?
      begin
        perms = JSON.parse(row['module_permissions'])
        if parsed.is_a?(Hash)
        parsed.each do |mod, permissions|
          next unless ALLOWED_MODULES.include?(mod)

          valid_perms = Array(permissions).select { |p| ALLOWED_PERMISSIONS.include?(p) }
          perms[mod] = valid_perms if valid_perms.any?
        end
      end
      rescue JSON::ParserError
        # ignore parse error
      end
    else
      modules = parse_modules(row['modules']).select { |m| ALLOWED_MODULES.include?(m) }

      modules.each do |mod|
        perms[mod] = ['read', 'write']
      end
    end
    attrs[:module_permissions] = perms
    attrs[:module_access] = perms.keys
    Role.find_or_initialize_by(name: attrs[:name]).tap { |r| r.update(attrs) }
  end

  def self.import_product(row)
    name = row['name'].to_s.encode('UTF-8', invalid: :replace, undef: :replace)
    variants_json = row['product_variants']
    specs_json = row['product_specifications'] || row['specifications']

    attrs = {
      name: name,
      sku: row['sku'],
      desc: row['desc'],
      material: row['material'],
      brand_id: resolve_brand_id(row),
      category_id: resolve_category_id(row),
      tax_rate: row['tax_rate'],
      is_active: parse_bool(row['is_active']),
      is_featured: parse_bool(row['is_featured']),
      is_new: parse_bool(row['is_new']),
      # DB columns are string-backed; keep stable JSON-string storage.
      features: parse_array(row['features']).to_json,
      care_instructions: parse_array(row['care_instructions']).to_json
    }

    prod = Product.find_or_initialize_by(sku: attrs[:sku])
    prod.assign_attributes(attrs)
    prod.slug = row['slug'] if row['slug'].present?

    parsed_variants = []
    if variants_json.present?
      begin
        parsed_variants = JSON.parse(variants_json)
        parsed_variants = [parsed_variants] unless parsed_variants.is_a?(Array)
      rescue => e
      end
    elsif row['variant_sku'].present?
      parsed_variants = [flat_variant_payload(row)]
    end

    if parsed_variants.present?
      parsed_variants.each do |variant|
        va = variant['variant_attributes'] || variant[:variant_attributes]
        normalized_attrs = parse_variant_attributes(va)
        variant['variant_attributes'] = normalized_attrs.to_json
      end
      prod.product_variants_attributes = parsed_variants
    end

    if specs_json.present?
      begin
        ps = JSON.parse(specs_json)
        if ps.is_a?(Hash)
          ps = ps.map { |k, v| { key: k.to_s, value: v.to_s } }
        elsif ps.is_a?(Array)
          ps = ps.map do |entry|
            if entry.is_a?(Hash)
              if entry['key'].present? || entry[:key].present?
                { key: (entry['key'] || entry[:key]).to_s, value: (entry['value'] || entry[:value]).to_s }
              else
                key, value = entry.first
                { key: key.to_s, value: value.to_s }
              end
            else
              nil
            end
          end.compact
        else
          ps = []
        end
        prod.product_specifications_attributes = ps
      rescue => e
      end
    elsif row['spec_key'].present? && row['spec_value'].present?
      prod.product_specifications_attributes = [{ key: row['spec_key'].to_s, value: row['spec_value'].to_s }]
    end

    prod.save!
    prod
  end

  def self.parse_bool(val)
    return false if val.nil?
    ['1','true','t','yes','y'].include?(val.to_s.downcase)
  end

  def self.parse_modules(val)
    return [] if val.blank?
    begin
      parsed = JSON.parse(val)
      return parsed if parsed.is_a?(Array)
    rescue
    end
    val.to_s.split('|').map(&:strip)
  end

  def self.parse_array(val)
    return [] if val.blank?
    return val if val.is_a?(Array)

    if val.is_a?(String)
      s = val.to_s.strip
      begin
        parsed = JSON.parse(s)
        return parsed if parsed.is_a?(Array)
      rescue JSON::ParserError
      end

      s = s.gsub(/\A\[/, "").gsub(/\]\z/, "")
      return s.split(/\r?\n|,|\|/).map { |x| x.to_s.strip.gsub(/\A['"]|['"]\z/, "") }.reject(&:blank?)
    end

    []
  end

  def self.resolve_brand_id(row)
    return row['brand_id'].to_i if row['brand_id'].present?

    if row['brand_slug'].present?
      b = Brand.find_by(slug: row['brand_slug'].to_s.parameterize)
      return b.id if b
    end
    if row['brand'].present?
      b = Brand.find_by(name: row['brand']) || Brand.find_by(slug: row['brand'].to_s.parameterize)
      return b.id if b
    end
    nil
  end

  def self.resolve_category_id(row)
    return row['category_id'].to_i if row['category_id'].present?

    if row['category_slug'].present?
      c = Category.find_by(slug: row['category_slug'].to_s.parameterize)
      return c.id if c
    end
    if row['category'].present?
      c = Category.find_by(name: row['category']) || Category.find_by(slug: row['category'].to_s.parameterize)
      return c.id if c
    end
    nil
  end

  def self.flat_variant_payload(row)
    {
      'variant_sku' => row['variant_sku'],
      'price' => row['price'].presence || row['selling_price'],
      'selling_price' => row['selling_price'].presence || row['price'],
      'dealer_price' => row['dealer_price'].presence || row['selling_price'] || row['price'],
      'dealer_selling_price' => row['dealer_selling_price'].presence || row['dealer_price'] || row['selling_price'] || row['price'],
      'is_active' => parse_bool(row['variant_is_active'].presence || row['is_variant_active'].presence || row['variant_active'].presence || 'true'),
      'variant_attributes' => row['variant_attributes']
    }
  end

  def self.parse_variant_attributes(value)
    return [] if value.blank?
    return value if value.is_a?(Array)
    return [value] if value.is_a?(Hash)

    s = value.to_s.strip
    begin
      parsed = JSON.parse(s)
      return parsed if parsed.is_a?(Array)
      return [parsed] if parsed.is_a?(Hash)
    rescue JSON::ParserError
    end

    # Supports "Color:Black|Size:Medium" style CSV values.
    pairs = s.split('|').map(&:strip).reject(&:blank?).map do |chunk|
      key, val = chunk.split(':', 2).map { |x| x.to_s.strip }
      next if key.blank? || val.blank?
      { key: key, value: val }
    end.compact
    pairs
  end
end
