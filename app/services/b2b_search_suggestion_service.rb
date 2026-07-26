class B2bSearchSuggestionService
  MAX_SUGGESTIONS = 10

  def initialize(buyer_dealer:, query:, pincode: nil)
    @buyer_dealer = buyer_dealer
    @query = query.to_s.strip
    @pincode = pincode.to_s.strip.presence || auto_capture_pincode
  end

  def call
    return [] if @query.length < 2

    wholesaler = wholesaler_suggestions
    b2b = b2b_product_suggestions

    merged = (wholesaler + b2b).uniq { |entry| entry[:label].downcase }
    merged.first(MAX_SUGGESTIONS)
  end

  private

  def auto_capture_pincode
    default_address = @buyer_dealer.addresses.where(is_default: true).first ||
                      @buyer_dealer.addresses.first
    default_address&.postal_code
  end

  def wholesaler_suggestions
    posts = WholesalerPost.visible_to_marketplace
                          .includes(dealer_product: { product: {} })
                          .where.not(dealer_id: @buyer_dealer.id)
                          .where(
                            "title ILIKE :q OR modal_no ILIKE :q OR body ILIKE :q",
                            q: "%#{@query}%"
                          )

    posts = posts.by_pincode(@pincode) if @pincode.present?

    posts.limit(20).filter_map do |post|
      product_name = post.dealer_product&.product&.name
      label = product_name.presence || post.title
      next if label.blank?

      {
        label: label,
        type: "wholesaler",
        dealer_product_id: post.dealer_product_id,
        wholesaler_post_id: post.id
      }
    end
  end

  def b2b_product_suggestions
    DealerProduct.live
                 .for_b2b
                 .where("dealer_products.stock_quantity > 0")
                 .where.not(dealer_id: @buyer_dealer.id)
                 .joins(:product)
                 .where("products.name ILIKE :q OR products.sku ILIKE :q", q: "%#{@query}%")
                 .includes(:product)
                 .limit(20)
                 .map do |row|
      {
        label: row.product.name,
        type: "b2b",
        dealer_product_id: row.id,
        product_slug: row.product.slug
      }
    end
  end
end
