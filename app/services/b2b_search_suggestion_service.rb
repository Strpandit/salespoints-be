class B2bSearchSuggestionService
  MAX_SUGGESTIONS = 10

  def initialize(buyer_dealer:, query:, pincode: nil)
    @buyer_dealer = buyer_dealer
    @query = query.to_s.strip
    @pincode = pincode.to_s.strip.presence || auto_capture_pincode
  end

  def call
    return [] if @query.length < 2

    # Get the raw comprehensive mapping
    search_data = self.class.matching_product_mapping(query: @query, buyer_dealer: @buyer_dealer, pincode: @pincode)
    
    wholesaler_posts = WholesalerPost.includes(dealer_product: :product)
                                     .where(id: search_data[:wholesaler_post_ids].values)
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

  # Returns a hash:
  # {
  #   wholesaler_post_ids: { product_id => wholesaler_post_id },
  #   b2b_product_ids: [product_id1, product_id2, ...]
  # }
  def self.matching_product_mapping(query:, buyer_dealer:, pincode: nil)
    return { wholesaler_post_ids: {}, b2b_product_ids: [] } if query.blank?

    q = "%#{query}%"

    # 1. Wholesaler Posts matching directly
    posts = WholesalerPost.visible_to_marketplace
                          .includes(:dealer_product)
                          .where.not(dealer_id: buyer_dealer.id)
                          .where(
                            "title ILIKE :q OR modal_no ILIKE :q OR body ILIKE :q",
                            q: q
                          )

    posts = posts.by_pincode(pincode.to_s) if pincode.present?

    wholesaler_mapping = {}
    posts.each do |post|
      dealer_product = post.dealer_product
      next unless dealer_product&.sellable_in_b2b? && dealer_product.stock_quantity.to_i.positive?
      wholesaler_mapping[dealer_product.product_id] = post.id
    end

    # 2. Comprehensive Dealer Products Search
    dealer_products = DealerProduct.live
                                   .for_b2b
                                   .where("dealer_products.stock_quantity > 0")
                                   .where.not(dealer_id: buyer_dealer.id)
                                   .joins(:product)
                                   .left_outer_joins(product: [:brand, :category])
                                   .left_outer_joins(product_variant: :product_variant_colors)
                                   .where(
                                     "products.name ILIKE :q OR 
                                      products.desc ILIKE :q OR 
                                      products.sku ILIKE :q OR 
                                      brands.name ILIKE :q OR 
                                      categories.name ILIKE :q OR 
                                      product_variants.variant_sku ILIKE :q OR 
                                      product_variant_colors.color_name ILIKE :q OR 
                                      dealer_products.ad_hoc_color ILIKE :q",
                                     q: q
                                   )

    b2b_product_ids = dealer_products.select(:product_id).distinct.pluck(:product_id)

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
      b2b_product_ids: b2b_product_ids
    }
  end

  private

  def auto_capture_pincode
    default_address = @buyer_dealer.addresses.where(is_default: true).first ||
                      @buyer_dealer.addresses.first
    default_address&.postal_code
  end
end
