require 'csv'

class BulkUploadService
  # import_type: brands, categories, cat_filters, roles, products
  # csv_data: string
  def self.import(import_type, csv_data)
    rows = CSV.parse(csv_data, headers: true)
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
    # expected headers: name, slug, description, is_active
    attrs = {
      name: row['name'],
      slug: row['slug'] || row['name'].to_s.parameterize,
      description: row['description'],
      is_active: parse_bool(row['is_active'])
    }
    Brand.find_or_initialize_by(slug: attrs[:slug]).tap { |b| b.update(attrs) }
  end

  def self.import_category(row)
    # expected headers: name, slug, parent_id, is_active
    attrs = {
      name: row['name'],
      slug: row['slug'] || row['name'].to_s.parameterize,
      parent_id: row['parent_id'].present? ? row['parent_id'].to_i : nil,
      is_active: parse_bool(row['is_active'])
    }
    Category.find_or_initialize_by(slug: attrs[:slug]).tap { |c| c.update(attrs) }
  end

  def self.import_cat_filter(row)
    # expected headers: name, key, category_id, is_active
    attrs = {
      name: row['name'],
      key: row['key'] || row['name'].to_s.parameterize.underscore,
      category_id: row['category_id'].present? ? row['category_id'].to_i : nil,
      is_active: parse_bool(row['is_active'])
    }
    CatFilter.find_or_initialize_by(key: attrs[:key]).tap { |f| f.update(attrs) }
  end

  def self.import_role(row)
    # expected headers: name, modules (json array or pipe-separated) OR module_permissions (json hash), is_active
    attrs = { name: row['name'], is_active: parse_bool(row['is_active']) }
    if row['module_permissions'].present?
      begin
        perms = JSON.parse(row['module_permissions'])
        attrs[:module_permissions] = perms
        # also set module_access as list of keys for compatibility
        attrs[:module_access] = perms.keys
      rescue
        # ignore parse error
      end
    else
      modules = parse_modules(row['modules'])
      attrs[:module_access] = modules
      # create simple module_permissions with write access by default
      perms = {}
      modules.each { |m| perms[m] = ['read','write'] }
      attrs[:module_permissions] = perms
    end
    Role.find_or_initialize_by(name: attrs[:name]).tap { |r| r.update(attrs) }
  end

  def self.import_product(row)
    # expected headers:
    # name, sku, slug, desc, brand_id, category_id, is_active, product_variants (JSON array), product_specifications (JSON array)
    variants_json = row['product_variants']
    specs_json = row['product_specifications']

    attrs = {
      name: row['name'],
      sku: row['sku'],
      slug: row['slug'] || row['name'].to_s.parameterize,
      desc: row['desc'],
      brand_id: row['brand_id'].present? ? row['brand_id'].to_i : nil,
      category_id: row['category_id'].present? ? row['category_id'].to_i : nil,
      is_active: parse_bool(row['is_active'])
    }

    prod = Product.find_or_initialize_by(sku: attrs[:sku])
    prod.assign_attributes(attrs)

    if variants_json.present?
      begin
        pv = JSON.parse(variants_json)
        prod.product_variants_attributes = pv
      rescue
        # ignore parse errors; will record on save
      end
    end

    if specs_json.present?
      begin
        ps = JSON.parse(specs_json)
        prod.product_specifications_attributes = ps
      rescue
      end
    end

    prod.save
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
    # fallback: pipe separated
    val.to_s.split('|').map(&:strip)
  end
end
