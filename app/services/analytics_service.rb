class AnalyticsService
  def self.get_dashboard_metrics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    {
      total_orders: base_query.count,
      total_revenue: base_query.sum(:total_amount),
      total_gmv: base_query.sum(:subtotal_amount),
      total_commission: base_query.sum(:commission_amount),
      total_marketplace_fee: base_query.sum(:marketplace_fee),
      successful_payments: base_query.where(payment_status: 'paid').count,
      failed_payments: base_query.where(payment_status: 'failed').count,
      pending_payments: base_query.where(payment_status: 'pending').count,
      refunded_orders: base_query.where(payment_status: ['partially_refunded', 'refunded']).count,
      active_sellers: base_query.distinct.pluck(:dealer_id).count,
      conversion_rate: calculate_conversion_rate(date_range, filters),
      average_order_value: base_query.average(:total_amount).to_f.round(2),
      top_products: get_top_products(date_range, filters),
      revenue_trend: get_revenue_trend(date_range, filters),
      order_trend: get_order_trend(date_range, filters),
      payment_method_breakdown: get_payment_method_breakdown(date_range, filters),
      category_performance: get_category_performance(date_range, filters),
      seller_performance: get_seller_performance(date_range, filters),
      geographic_distribution: get_geographic_distribution(date_range, filters)
    }
  end

  def self.get_revenue_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    {
      total_revenue: base_query.sum(:total_amount),
      total_gmv: base_query.sum(:subtotal_amount),
      total_commission: base_query.sum(:commission_amount),
      total_marketplace_fee: base_query.sum(:marketplace_fee),
      revenue_by_payment_method: base_query.group(:payment_method).sum(:total_amount),
      revenue_by_category: get_revenue_by_category(date_range, filters),
      revenue_by_seller: get_revenue_by_seller(date_range, filters),
      monthly_revenue_trend: get_monthly_revenue_trend(date_range, filters),
      commission_trend: get_commission_trend(date_range, filters)
    }
  end

  def self.get_order_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    {
      total_orders: base_query.count,
      completed_orders: base_query.where(status: 'delivered').count,
      pending_orders: base_query.where(status: ['pending', 'processing', 'shipped']).count,
      cancelled_orders: base_query.where(status: 'cancelled').count,
      order_status_distribution: base_query.group(:status).count,
      average_order_value: base_query.average(:total_amount).to_f.round(2),
      order_trend: get_order_trend(date_range, filters),
      order_conversion_funnel: get_order_conversion_funnel(date_range, filters),
      order_value_distribution: get_order_value_distribution(date_range, filters)
    }
  end

  def self.get_payment_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    payment_attempts = PaymentAttempt.where(created_at: date_range)
    payment_attempts = payment_attempts.joins(:order).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && user_type == 'dealer'

    {
      total_payment_attempts: payment_attempts.count,
      successful_payments: payment_attempts.where(status: 'paid').count,
      failed_payments: payment_attempts.where(status: 'failed').count,
      pending_payments: payment_attempts.where(status: 'pending').count,
      payment_success_rate: calculate_payment_success_rate(payment_attempts),
      payment_method_distribution: payment_attempts.group(:payment_method).count,
      payment_failure_reasons: get_payment_failure_reasons(payment_attempts),
      payment_amount_distribution: get_payment_amount_distribution(payment_attempts),
      payment_trend: get_payment_trend(date_range, filters)
    }
  end

  def self.get_seller_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')

    dealers = Dealer.all
    dealer_metrics = dealers.map do |dealer|
      orders = dealer.orders.where(created_at: date_range)
      settlements = dealer.settlements.where(created_at: date_range)
      payouts = dealer.dealer_payouts.where(created_at: date_range)

      {
        dealer_id: dealer.id,
        dealer_name: dealer.full_name,
        total_orders: orders.count,
        total_revenue: orders.sum(:seller_settlement_amount),
        total_commission: orders.sum(:commission_amount),
        pending_settlements: settlements.where(status: 'pending').sum(:amount),
        completed_payouts: payouts.where(status: 'paid').sum(:amount),
        current_balance: dealer.settlement_balance,
        performance_score: calculate_seller_performance_score(dealer, date_range)
      }
    end

    dealer_metrics.sort_by { |m| m[:total_revenue] }.reverse
  end

  def self.get_product_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    order_items = OrderItem.joins(:order).where(orders: { created_at: date_range })
    order_items = order_items.joins(order: :dealer).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && user_type == 'dealer'

    product_metrics = order_items.group(:product_id).select(
      'product_id',
      'COUNT(*) as total_sold',
      'SUM(quantity) as total_quantity',
      'SUM(total_price) as total_revenue',
      'AVG(price) as average_price'
    ).map do |item|
      product = Product.find_by(id: item.product_id)
      next unless product

      {
        product_id: product.id,
        product_name: product.name,
        category: product.category&.name,
        total_sold: item.total_sold,
        total_quantity: item.total_quantity,
        total_revenue: item.total_revenue,
        average_price: item.average_price,
        performance_score: calculate_product_performance_score(item)
      }
    end.compact

    product_metrics.sort_by { |p| p[:total_revenue] }.reverse
  end

  def self.get_customer_analytics(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')

    customers = User.where(created_at: date_range).or(User.where('last_sign_in_at >= ?', date_range.first))
    customer_metrics = customers.map do |customer|
      orders = customer.orders.where(created_at: date_range)
      total_spent = orders.sum(:total_amount)
      order_count = orders.count

      {
        customer_id: customer.id,
        customer_name: customer.name,
        email: customer.email,
        total_orders: order_count,
        total_spent: total_spent,
        average_order_value: order_count > 0 ? (total_spent / order_count).round(2) : 0,
        last_order_date: orders.maximum(:created_at),
        customer_segment: determine_customer_segment(total_spent, order_count),
        lifetime_value: customer.orders.sum(:total_amount)
      }
    end

    customer_metrics.sort_by { |c| c[:total_spent] }.reverse
  end

  private

  def self.parse_date_range(period)
    case period
    when 'daily'
      1.day.ago.beginning_of_day..Time.current.end_of_day
    when 'weekly'
      1.week.ago.beginning_of_week..Time.current.end_of_week
    when 'monthly'
      1.month.ago.beginning_of_month..Time.current.end_of_month
    when 'quarterly'
      3.months.ago.beginning_of_quarter..Time.current.end_of_quarter
    when 'half_yearly'
      6.months.ago.beginning_of_month..Time.current.end_of_month
    when 'yearly'
      1.year.ago.beginning_of_year..Time.current.end_of_year
    else
      1.month.ago.beginning_of_month..Time.current.end_of_month
    end
  end

  def self.calculate_conversion_rate(date_range, filters)
    # This would need visitor tracking data
    # For now, return a placeholder calculation
    orders = Order.where(created_at: date_range)
    orders = orders.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    # Placeholder: assume 5% conversion rate
    5.0
  end

  def self.get_top_products(date_range, filters)
    order_items = OrderItem.joins(:order).where(orders: { created_at: date_range })
    order_items = order_items.joins(order: :dealer).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    order_items.group(:product_id)
              .select('product_id, SUM(quantity) as total_quantity, SUM(total_price) as total_revenue')
              .order('total_revenue DESC')
              .limit(10)
              .map do |item|
                product = Product.find_by(id: item.product_id)
                next unless product
                {
                  product_id: product.id,
                  product_name: product.name,
                  total_quantity: item.total_quantity,
                  total_revenue: item.total_revenue
                }
              end.compact
  end

  def self.get_revenue_trend(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.group_by_day(:created_at).sum(:total_amount)
  end

  def self.get_order_trend(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.group_by_day(:created_at).count
  end

  def self.get_payment_method_breakdown(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.group(:payment_method).count
  end

  def self.get_category_performance(date_range, filters)
    order_items = OrderItem.joins(:order, :product => :category)
                          .where(orders: { created_at: date_range })
    order_items = order_items.joins(order: :dealer).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    order_items.group('categories.name')
              .select('categories.name as category_name, COUNT(*) as total_orders, SUM(order_items.total_price) as total_revenue')
              .order('total_revenue DESC')
              .map do |item|
                {
                  category: item.category_name,
                  total_orders: item.total_orders,
                  total_revenue: item.total_revenue
                }
              end
  end

  def self.get_seller_performance(date_range, filters)
    return [] if filters[:user_type] == 'dealer' # Dealers don't see other sellers

    Order.where(created_at: date_range)
         .joins(:dealer)
         .group('dealers.id, dealers.full_name')
         .select('dealers.id, dealers.full_name, COUNT(*) as total_orders, SUM(orders.total_amount) as total_revenue')
         .order('total_revenue DESC')
         .limit(10)
         .map do |item|
           {
             seller_id: item.id,
             seller_name: item.full_name,
             total_orders: item.total_orders,
             total_revenue: item.total_revenue
           }
         end
  end

  def self.get_geographic_distribution(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.joins(:billing_address)
              .group('addresses.state')
              .select('addresses.state, COUNT(*) as total_orders, SUM(orders.total_amount) as total_revenue')
              .order('total_revenue DESC')
              .map do |item|
                {
                  state: item.state,
                  total_orders: item.total_orders,
                  total_revenue: item.total_revenue
                }
              end
  end

  def self.get_revenue_by_category(date_range, filters)
    get_category_performance(date_range, filters)
  end

  def self.get_revenue_by_seller(date_range, filters)
    get_seller_performance(date_range, filters)
  end

  def self.get_monthly_revenue_trend(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.group_by_month(:created_at).sum(:total_amount)
  end

  def self.get_commission_trend(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    base_query.group_by_month(:created_at).sum(:commission_amount)
  end

  def self.get_order_conversion_funnel(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    {
      initiated: base_query.count,
      paid: base_query.where(payment_status: 'paid').count,
      processing: base_query.where(status: 'processing').count,
      shipped: base_query.where(status: 'shipped').count,
      delivered: base_query.where(status: 'delivered').count
    }
  end

  def self.get_order_value_distribution(date_range, filters)
    base_query = Order.where(created_at: date_range)
    base_query = base_query.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    # Group by price ranges
    ranges = [
      { min: 0, max: 500, label: '₹0 - ₹500' },
      { min: 500, max: 1000, label: '₹500 - ₹1,000' },
      { min: 1000, max: 2500, label: '₹1,000 - ₹2,500' },
      { min: 2500, max: 5000, label: '₹2,500 - ₹5,000' },
      { min: 5000, max: Float::INFINITY, label: '₹5,000+' }
    ]

    ranges.map do |range|
      count = base_query.where(total_amount: range[:min]..range[:max]).count
      {
        range: range[:label],
        count: count,
        percentage: base_query.count > 0 ? (count.to_f / base_query.count * 100).round(1) : 0
      }
    end
  end

  def self.calculate_payment_success_rate(payment_attempts)
    total = payment_attempts.count
    successful = payment_attempts.where(status: 'paid').count
    total > 0 ? (successful.to_f / total * 100).round(1) : 0
  end

  def self.get_payment_failure_reasons(payment_attempts)
    payment_attempts.where(status: 'failed')
                   .group(:failure_reason)
                   .count
                   .map { |reason, count| { reason: reason || 'Unknown', count: count } }
  end

  def self.get_payment_amount_distribution(payment_attempts)
    get_order_value_distribution(payment_attempts.first&.order&.created_at&.all_month || 1.month.ago.all_month, {})
  end

  def self.get_payment_trend(date_range, filters)
    payment_attempts = PaymentAttempt.where(created_at: date_range)
    payment_attempts = payment_attempts.joins(:order).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && filters[:user_type] == 'dealer'

    payment_attempts.group_by_day(:created_at).count
  end

  def self.calculate_seller_performance_score(dealer, date_range)
    orders = dealer.orders.where(created_at: date_range)
    return 0 if orders.empty?

    revenue = orders.sum(:total_amount)
    order_count = orders.count
    delivered_count = orders.where(status: 'delivered').count
    delivery_rate = order_count > 0 ? delivered_count.to_f / order_count : 0

    # Simple scoring algorithm
    revenue_score = [revenue / 10000, 10].min # Max 10 points for revenue
    volume_score = [order_count / 10, 10].min # Max 10 points for volume
    quality_score = delivery_rate * 10 # 0-10 points for delivery rate

    ((revenue_score + volume_score + quality_score) / 3).round(1)
  end

  def self.calculate_product_performance_score(item)
    revenue_score = [item.total_revenue / 1000, 10].min
    volume_score = [item.total_quantity / 10, 10].min

    ((revenue_score + volume_score) / 2).round(1)
  end

  def self.determine_customer_segment(total_spent, order_count)
    if total_spent >= 50000 || order_count >= 50
      'VIP'
    elsif total_spent >= 25000 || order_count >= 25
      'Gold'
    elsif total_spent >= 10000 || order_count >= 10
      'Silver'
    else
      'Bronze'
    end
  end
end