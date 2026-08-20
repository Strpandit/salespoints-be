require "ostruct"

class WholesalerPostCatalogWrapper
  attr_reader :wholesaler_post, :dealer, :product, :product_variant

  def initialize(wholesaler_post)
    @wholesaler_post = wholesaler_post
    @dealer = wholesaler_post.dealer

    if wholesaler_post.dealer_product.present?
      @product = wholesaler_post.dealer_product.product
      @product_variant = wholesaler_post.dealer_product.product_variant
    else
      @product = OpenStruct.new(
        id: "wp_#{wholesaler_post.id}",
        name: wholesaler_post.title,
        slug: "wholesaler-#{wholesaler_post.id}",
        desc: wholesaler_post.body,
        hsn_code: wholesaler_post.hsn_code,
        average_rating: wholesaler_post.rating.to_f,
        review_count: wholesaler_post.rating_count.to_i,
        discount_percentage: 0,
        brand: nil,
        category: nil
      )
      @product_variant = OpenStruct.new(
        id: "wpv_#{wholesaler_post.id}",
        variant_name: wholesaler_post.title,
        variant_sku: wholesaler_post.modal_no || "MOD-#{wholesaler_post.id}",
        selling_price: wholesaler_post.price.to_f,
        dealer_price: wholesaler_post.price.to_f,
        dealer_selling_price: wholesaler_post.price.to_f,
        price: wholesaler_post.price.to_f,
        discount_percentage: 0,
        hsn_code: wholesaler_post.hsn_code,
        variant_attributes: []
      )
    end
  end

  def id
    "wp_#{wholesaler_post.id}"
  end

  def stock_quantity
    wholesaler_post.stock_quantity.to_i
  end

  def color_stocks
    {}
  end

  def is_active
    true
  end

  def approve_status
    wholesaler_post.approve_status
  end

  def sell_in_b2b
    true
  end

  def sell_in_b2c
    false
  end

  def created_at
    wholesaler_post.created_at
  end

  def updated_at
    wholesaler_post.updated_at
  end

  def distance_km
    wholesaler_post.respond_to?(:distance_km) ? wholesaler_post.distance_km : nil
  end

  def listing_priority
    0
  end

  def from_wholesaler
    true
  end

  def wholesaler_post_id
    wholesaler_post.id
  end

  def effective_hsn_code
    wholesaler_post.effective_hsn_code
  end

  def display_media_attachments
    wholesaler_post.media
  end

  def display_primary_blob_id
    wholesaler_post.media.first&.blob_id
  end
end

class B2bShopCatalogService
  PRIORITY_WHOLESALER = 0
  PRIORITY_B2B = 1

  def initialize(buyer_dealer:, params:)
    @buyer_dealer = buyer_dealer
    @params = params
    @google_maps = GoogleMapsService.instance
  end

  def call
    if @params[:search].present?
      query = @params[:search].strip
      pincode = @params[:pincode].presence || @params[:postal_code].presence
      @search_mapping = B2bSearchSuggestionService.matching_product_mapping(query: query, buyer_dealer: @buyer_dealer, pincode: pincode)
    end

    coords = resolve_buyer_coordinates

    if coords.blank?
      rows = base_scope.to_a
      rows.each { |row| row.define_singleton_method(:distance_km) { nil } }
      grouped = group_products(rows)
      sorted = sort_rows(grouped)
      prioritized = prioritize_wholesaler_matches(sorted)
      return paginate(prioritized)
    end

    radius = resolved_radius
    rows = filter_rows_within_radius(base_scope.to_a, coords, radius)
    grouped = group_products(rows)
    sorted = sort_rows(grouped)
    prioritized = prioritize_wholesaler_matches(sorted)

    paginate(prioritized)
  end

  private

  def resolve_buyer_coordinates
    lat = @params[:latitude].presence&.to_f
    lng = @params[:longitude].presence&.to_f
    return { latitude: lat, longitude: lng } if lat.present? && lng.present? && !lat.zero? && !lng.zero?

    pincode = @params[:pincode].presence || @params[:postal_code].presence
    return geocode_pincode(pincode.to_s.strip) if pincode.present?

    nil
  end

  def geocode_pincode(pincode)
    return nil if pincode.blank?

    B2bPincodeAvailabilityService.geocode_pincode(pincode.to_s.strip) if pincode.present?
  end

  def resolved_radius
    custom = @params[:radius_km].to_f
    return custom if custom.positive?

    configured = @buyer_dealer.dealer_location&.service_radius_km.to_f
    return configured if configured.positive?

    5.0
  end

  def base_scope
    items = DealerProduct.live
                        .for_b2b
                        .where("dealer_products.stock_quantity > 0")
                        .where.not(dealer_id: @buyer_dealer.id)
                        .includes(dealer: :dealer_location, product: { brand: {} }, product_variant: {})

    if @params[:category_id].present?
      items = items.joins(:product).where(products: { category_id: @params[:category_id] })
    end

    items = items.where(product_id: @params[:product_id]) if @params[:product_id].present?
    items = items.where(product_variant_id: @params[:product_variant_id]) if @params[:product_variant_id].present?

    if @params[:search].present? && @search_mapping
      matched_product_ids = (@search_mapping[:b2b_product_ids] + @search_mapping[:wholesaler_post_ids].keys).uniq
      if matched_product_ids.empty?
        items = items.none
      else
        items = items.where(product_id: matched_product_ids)
      end
    end

    if @params[:brands].present? && @params[:brands].is_a?(Array)
      items = items.joins(product: :brand)
                  .where("LOWER(brands.name) IN (?)", @params[:brands].map(&:downcase))
    end

    if @params[:min_price].present?
      min_price = @params[:min_price].to_f
      items = items.joins(:product_variant)
                  .where(Arel.sql("COALESCE(product_variants.dealer_selling_price, product_variants.dealer_price) >= ?"), min_price)
    end

    if @params[:max_price].present?
      max_price = @params[:max_price].to_f
      items = items.joins(:product_variant)
                  .where(Arel.sql("COALESCE(product_variants.dealer_selling_price, product_variants.dealer_price) <= ?"), max_price)
    end

    items
  end

  def filter_rows_within_radius(rows, coords, radius)
    rows.select do |row|
      seller_location = row.dealer&.dealer_location
      next false unless seller_location&.is_active && seller_location.latitude.present? && seller_location.longitude.present?

      distance = driving_distance_km(
        coords[:latitude],
        coords[:longitude],
        seller_location.latitude.to_f,
        seller_location.longitude.to_f
      )

      row.define_singleton_method(:distance_km) { distance.round(2) }

      seller_radius = seller_location.service_radius_km.to_f
      seller_radius = radius if seller_radius <= 0
      distance <= radius && distance <= seller_radius
    end
  end

  def driving_distance_km(lat1, lng1, lat2, lng2)
    info = @google_maps.driving_distance(lat1, lng1, lat2, lng2)
    return info[:distance_km] if info.present?

    DealerLocation.distance_km(lat1, lng1, lat2, lng2)
  end

  def group_products(rows)
    grouped = rows.group_by(&:product_id)

    if @params[:ratings].present? && @params[:ratings].is_a?(Array)
      min_rating = @params[:ratings].min.to_i
      grouped = grouped.select do |product_id, dealer_products|
        product = dealer_products.first&.product
        next false unless product
        product.average_rating >= min_rating
      end
    end

    grouped.values.map do |dealer_products|
      representative = dealer_products.min_by do |row|
        row.respond_to?(:distance_km) ? (row.distance_km || Float::INFINITY) : Float::INFINITY
      end

      total_stock = dealer_products.sum(&:stock_quantity)

      representative.define_singleton_method(:stock_quantity) do
        total_stock
      end

      representative
    end
  end

  def pick_nearest_per_variant(rows)
    best_by_variant = {}

    rows.each do |row|
      vid = row.product_variant_id
      distance = row.respond_to?(:distance_km) ? row.distance_km : Float::INFINITY
      distance = Float::INFINITY if distance.nil?
      prev = best_by_variant[vid]
      best_by_variant[vid] = [row, distance] if prev.nil? || distance < prev[1]
    end

    best_by_variant.values.map do |row, distance|
      row.define_singleton_method(:distance_km) { distance.round(2) }
      row
    end
  end

  def sort_rows(rows)
    case @params[:sort]
    when "price_asc"
      rows.sort_by { |row| row.product_variant&.dealer_selling_price.to_f }
    when "price_desc"
      rows.sort_by { |row| -row.product_variant&.dealer_selling_price.to_f }
    when "a_to_z"
      rows.sort_by { |row| row.product&.name.to_s.downcase }
    when "z_to_a"
      rows.sort_by { |row| -row.product&.name.to_s.downcase }
    when "newest"
      rows.sort_by { |row| row.product&.created_at || Time.current }.reverse
    else
      rows.sort_by do |row|
        distance = row.respond_to?(:distance_km) ? row.distance_km : Float::INFINITY
        distance = Float::INFINITY if distance.nil?
        [distance, row.created_at]
      end
    end
  end

  def prioritize_wholesaler_matches(rows)
    rows.each do |row|
      row.define_singleton_method(:listing_priority) { PRIORITY_B2B } unless row.respond_to?(:listing_priority)
      row.define_singleton_method(:from_wholesaler) { false } unless row.respond_to?(:from_wholesaler)
      row.define_singleton_method(:wholesaler_post_id) { nil } unless row.respond_to?(:wholesaler_post_id)
    end

    return rows if @params[:search].blank? || @search_mapping.nil?

    wholesaler_ids = (@search_mapping[:wholesaler_post_ids].values + (@search_mapping[:standalone_wholesaler_post_ids] || [])).uniq
    return rows if wholesaler_ids.empty?

    wholesaler_posts = WholesalerPost.visible_to_marketplace
                                     .includes(:dealer, dealer_product: [:product, :product_variant])
                                     .where(id: wholesaler_ids)

    pincode = @params[:pincode].presence || @params[:postal_code].presence
    wholesaler_posts = wholesaler_posts.by_pincode(pincode.to_s) if pincode.present?

    wholesaler_wrappers = wholesaler_posts.map do |post|
      WholesalerPostCatalogWrapper.new(post)
    end

    combined = wholesaler_wrappers + rows

    combined.sort_by do |row|
      priority = row.respond_to?(:listing_priority) ? row.listing_priority : PRIORITY_B2B
      dist = row.respond_to?(:distance_km) ? (row.distance_km || Float::INFINITY) : Float::INFINITY
      [priority, dist]
    end
  end

  def paginate(prioritized)
    page = @params[:page].to_i
    page = 1 if page <= 0
    per_page = (@params[:per_page].presence || 20).to_i
    per_page = 20 if per_page <= 0

    Kaminari.paginate_array(prioritized).page(page).per(per_page)
  end
end

