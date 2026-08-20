class B2bSearchSuggestionService
  MAX_SUGGESTIONS = 10

  def initialize(buyer_dealer:, query:, pincode: nil)
    @buyer_dealer = buyer_dealer
    @query = query.to_s.strip
    @pincode = pincode.to_s.strip.presence || auto_capture_pincode
  end

  def call
    return [] if @query.length < 2

    search_data = self.class.matching_product_mapping(query: @query, buyer_dealer: @buyer_dealer, pincode: @pincode)

    all_wholesaler_post_ids = (search_data[:wholesaler_post_ids].values + search_data[:standalone_wholesaler_post_ids]).uniq
    wholesaler_posts = WholesalerPost.includes(dealer_product: :product)
                                     .where(id: all_wholesaler_post_ids)
                                     .limit(20)

    b2b_products = DealerProduct.includes(:product)
                                .where(product_id: search_data[:b2b_product_ids])
                                .limit(20)

    wholesaler = wholesaler_posts.filter_map do |post|
      label = post.dealer_product&.product&.name.presence || post.title
      next if label.blank?
      {
        label: label,
        type: "wholesaler",
        dealer_product_id: post.dealer_product_id,
        wholesaler_post_id: post.id
      }
    end

    b2b = b2b_products.filter_map do |row|
      next unless row.product
      {
        label: row.product.name,
        type: "b2b",
        dealer_product_id: row.id,
        product_slug: row.product.slug
      }
    end

    merged = (wholesaler + b2b).uniq { |entry| entry[:label].downcase }
    merged.first(MAX_SUGGESTIONS)
  end

  def self.matching_product_mapping(query:, buyer_dealer:, pincode: nil)
    return { wholesaler_post_ids: {}, standalone_wholesaler_post_ids: [], b2b_product_ids: [] } if query.blank?

    posts = find_wholesaler_posts(query, buyer_dealer, pincode)

    wholesaler_mapping = {}
    standalone_post_ids = []

    posts.each do |post|
      dealer_product = post.dealer_product
      if dealer_product&.sellable_in_b2b? && dealer_product.stock_quantity.to_i.positive?
        wholesaler_mapping[dealer_product.product_id] = post.id
      else
        standalone_post_ids << post.id if post.stock_quantity.to_i.positive?
      end
    end

    b2b_product_ids = find_dealer_products(query, buyer_dealer)

    # Catch products matched comprehensively that also have active wholesaler posts
    if b2b_product_ids.any?
      additional_posts = WholesalerPost.visible_to_marketplace
                                       .joins(:dealer_product)
                                       .where(dealer_products: { product_id: b2b_product_ids })
                                       .where.not(dealer_id: buyer_dealer.id)

      additional_posts = additional_posts.by_pincode(pincode.to_s) if pincode.present?

      additional_posts.each do |post|
        next unless post.dealer_product&.sellable_in_b2b? && post.dealer_product.stock_quantity.to_i.positive?
        wholesaler_mapping[post.dealer_product.product_id] ||= post.id
      end
    end

    {
      wholesaler_post_ids: wholesaler_mapping,
      standalone_wholesaler_post_ids: standalone_post_ids.uniq,
      b2b_product_ids: b2b_product_ids.uniq
    }
  end

  def self.extract_tokens(query)
    clean = query.to_s.strip.downcase.gsub(/[^a-z0-9\.\-]/, " ")
    tokens = clean.split(/\s+/).reject { |t| t.blank? || t.length < 2 }
    tokens = [query.strip.downcase] if tokens.empty? && query.present?
    tokens.uniq
  end

  def self.find_wholesaler_posts(query, buyer_dealer, pincode)
    tokens = extract_tokens(query)
    base = WholesalerPost.visible_to_marketplace
                         .left_outer_joins(dealer: :dealer_profile, dealer_product: [:product, :product_variant])
                         .where.not(dealer_id: buyer_dealer.id)
    base = base.by_pincode(pincode.to_s) if pincode.present?

    return WholesalerPost.none if tokens.empty?

    scope = base
    tokens.each do |t|
      pattern = "%#{t}%"
      scope = scope.where(
        "wholesaler_posts.title ILIKE :p OR " \
        "wholesaler_posts.body ILIKE :p OR " \
        "wholesaler_posts.modal_no ILIKE :p OR " \
        "wholesaler_posts.hsn_code ILIKE :p OR " \
        "wholesaler_posts.ad_hoc_color ILIKE :p OR " \
        "dealer_profiles.business_name ILIKE :p OR " \
        "dealers.first_name ILIKE :p OR " \
        "dealers.last_name ILIKE :p OR " \
        "dealers.dealer_code ILIKE :p OR " \
        "products.name ILIKE :p OR " \
        "products.desc ILIKE :p OR " \
        "products.sku ILIKE :p OR " \
        "product_variants.variant_sku ILIKE :p",
        p: pattern
      )
    end

    results = scope.to_a
    return results if results.any?

    pattern = "%#{query.strip}%"
    base.where(
      "wholesaler_posts.title ILIKE :p OR " \
      "wholesaler_posts.body ILIKE :p OR " \
      "wholesaler_posts.modal_no ILIKE :p OR " \
      "wholesaler_posts.hsn_code ILIKE :p OR " \
      "wholesaler_posts.ad_hoc_color ILIKE :p OR " \
      "dealer_profiles.business_name ILIKE :p OR " \
      "dealers.first_name ILIKE :p OR " \
      "dealers.last_name ILIKE :p OR " \
      "dealers.dealer_code ILIKE :p OR " \
      "products.name ILIKE :p OR " \
      "products.desc ILIKE :p OR " \
      "products.sku ILIKE :p OR " \
      "product_variants.variant_sku ILIKE :p",
      p: pattern
    ).to_a
  end

  def self.find_dealer_products(query, buyer_dealer)
    tokens = extract_tokens(query)
    base = DealerProduct.live
                        .for_b2b
                        .where("dealer_products.stock_quantity > 0")
                        .where.not(dealer_id: buyer_dealer.id)
                        .joins(:product)
                        .left_outer_joins(dealer: :dealer_profile)
                        .left_outer_joins(product: [:brand, :category, :product_specifications])
                        .left_outer_joins(product_variant: :product_variant_colors)

    return [] if tokens.empty?

    scope = base
    tokens.each do |t|
      pattern = "%#{t}%"
      scope = scope.where(
        "products.name ILIKE :p OR " \
        "products.desc ILIKE :p OR " \
        "products.sku ILIKE :p OR " \
        "products.hsn_code ILIKE :p OR " \
        "products.features ILIKE :p OR " \
        "brands.name ILIKE :p OR " \
        "categories.name ILIKE :p OR " \
        "product_variants.variant_sku ILIKE :p OR " \
        "product_variants.hsn_code ILIKE :p OR " \
        "product_variant_colors.color_name ILIKE :p OR " \
        "product_specifications.key ILIKE :p OR " \
        "product_specifications.value ILIKE :p OR " \
        "dealer_profiles.business_name ILIKE :p OR " \
        "dealers.first_name ILIKE :p OR " \
        "dealers.last_name ILIKE :p OR " \
        "dealers.dealer_code ILIKE :p",
        p: pattern
      )
    end

    product_ids = scope.distinct.pluck(:product_id)
    return product_ids if product_ids.any?

    pattern = "%#{query.strip}%"
    base.where(
      "products.name ILIKE :p OR " \
      "products.desc ILIKE :p OR " \
      "products.sku ILIKE :p OR " \
      "products.hsn_code ILIKE :p OR " \
      "brands.name ILIKE :p OR " \
      "categories.name ILIKE :p OR " \
      "product_variants.variant_sku ILIKE :p OR " \
      "product_variant_colors.color_name ILIKE :p OR " \
      "product_specifications.key ILIKE :p OR " \
      "product_specifications.value ILIKE :p OR " \
      "dealer_profiles.business_name ILIKE :p OR " \
      "dealers.first_name ILIKE :p OR " \
      "dealers.last_name ILIKE :p OR " \
      "dealers.dealer_code ILIKE :p",
      p: pattern
    ).distinct.pluck(:product_id)
  end

  private

  def auto_capture_pincode
    default_address = @buyer_dealer.addresses.where(is_default: true).first ||
                      @buyer_dealer.addresses.first
    default_address&.postal_code
  end
end

