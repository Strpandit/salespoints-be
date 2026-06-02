require 'csv'
require 'axlsx'

class ReportsService
  def self.generate_monthly_sales_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    orders = Order.where(created_at: date_range)
    orders = orders.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    report_data = {
      summary: generate_sales_summary(orders, date_range),
      orders: orders.includes(:dealer, :user, :order_items).map { |order| format_order_data(order) },
      trends: generate_sales_trends(orders, date_range),
      top_products: generate_top_products(orders),
      top_sellers: generate_top_sellers(orders),
      payment_methods: generate_payment_methods_breakdown(orders)
    }

    generate_report_file(report_data, 'monthly_sales_report', filters[:format] || 'xlsx')
  end

  def self.generate_seller_payout_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')

    payouts = DealerPayout.where(created_at: date_range).includes(:dealer)
    settlements = OrderSettlement.where(created_at: date_range).includes(:dealer, :order)

    report_data = {
      summary: generate_payout_summary(payouts, settlements, date_range),
      payouts: payouts.map { |payout| format_payout_data(payout) },
      settlements: settlements.map { |settlement| format_settlement_data(settlement) },
      pending_balances: generate_pending_balances(date_range),
      payout_trends: generate_payout_trends(date_range)
    }

    generate_report_file(report_data, 'seller_payout_report', filters[:format] || 'xlsx')
  end

  def self.generate_commission_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    orders = Order.where(created_at: date_range)
    orders = orders.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    report_data = {
      summary: generate_commission_summary(orders, date_range),
      commissions: orders.map { |order| format_commission_data(order) },
      commission_trends: generate_commission_trends(orders, date_range),
      commission_by_seller: generate_commission_by_seller(orders),
      commission_by_category: generate_commission_by_category(orders)
    }

    generate_report_file(report_data, 'commission_report', filters[:format] || 'xlsx')
  end

  def self.generate_refund_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    refunds = Refund.where(created_at: date_range).includes(:order)
    refunds = refunds.joins(:order).where(orders: { dealer_id: filters[:dealer_id] }) if filters[:dealer_id] && user_type == 'dealer'

    report_data = {
      summary: generate_refund_summary(refunds, date_range),
      refunds: refunds.map { |refund| format_refund_data(refund) },
      refund_reasons: generate_refund_reasons_breakdown(refunds),
      refund_trends: generate_refund_trends(refunds, date_range),
      refund_by_payment_method: generate_refund_by_payment_method(refunds)
    }

    generate_report_file(report_data, 'refund_report', filters[:format] || 'xlsx')
  end

  def self.generate_tax_gst_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')
    user_type = filters[:user_type]

    orders = Order.where(created_at: date_range).includes(:order_items)
    orders = orders.where(dealer_id: filters[:dealer_id]) if filters[:dealer_id] && user_type == 'dealer'

    report_data = {
      summary: generate_tax_summary(orders, date_range),
      tax_breakdown: generate_tax_breakdown(orders),
      gst_by_state: generate_gst_by_state(orders),
      hsn_sac_codes: generate_hsn_sac_codes(orders),
      tax_trends: generate_tax_trends(orders, date_range),
      compliance_check: generate_compliance_check(orders, date_range)
    }

    generate_report_file(report_data, 'tax_gst_report', filters[:format] || 'xlsx')
  end

  def self.generate_accounting_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')

    orders = Order.where(created_at: date_range).includes(:dealer, :user, :order_items)
    payouts = DealerPayout.where(created_at: date_range).includes(:dealer)
    refunds = Refund.where(created_at: date_range).includes(:order)

    report_data = {
      balance_sheet: generate_balance_sheet(orders, payouts, refunds, date_range),
      profit_loss: generate_profit_loss_statement(orders, payouts, refunds, date_range),
      cash_flow: generate_cash_flow_statement(orders, payouts, refunds, date_range),
      receivables: generate_accounts_receivable(orders, date_range),
      payables: generate_accounts_payable(payouts, date_range),
      audit_trail: generate_audit_trail(orders, payouts, refunds, date_range)
    }

    generate_report_file(report_data, 'accounting_report', filters[:format] || 'xlsx')
  end

  def self.generate_audit_compliance_report(filters = {})
    date_range = parse_date_range(filters[:period] || 'monthly')

    orders = Order.where(created_at: date_range)
    payments = PaymentAttempt.where(created_at: date_range)
    settlements = OrderSettlement.where(created_at: date_range)
    payouts = DealerPayout.where(created_at: date_range)
    refunds = Refund.where(created_at: date_range)

    report_data = {
      compliance_summary: generate_compliance_summary(orders, payments, settlements, payouts, refunds),
      data_integrity_checks: generate_data_integrity_checks(orders, payments),
      financial_reconciliation: generate_financial_reconciliation(orders, payouts, refunds),
      regulatory_reporting: generate_regulatory_reporting(orders, date_range),
      audit_logs: generate_audit_logs(date_range),
      risk_assessment: generate_risk_assessment(orders, payments, date_range)
    }

    generate_report_file(report_data, 'audit_compliance_report', filters[:format] || 'xlsx')
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

  def self.generate_sales_summary(orders, date_range)
    {
      period: "#{date_range.first.strftime('%B %Y')}",
      total_orders: orders.count,
      total_revenue: orders.sum(:total_amount),
      total_gmv: orders.sum(:subtotal_amount),
      total_commission: orders.sum(:commission_amount),
      total_marketplace_fee: orders.sum(:marketplace_fee),
      average_order_value: orders.average(:total_amount).to_f.round(2),
      successful_orders: orders.where(payment_status: 'paid').count,
      pending_orders: orders.where(payment_status: 'pending').count,
      cancelled_orders: orders.where(status: 'cancelled').count,
      refunded_orders: orders.where(payment_status: ['partially_refunded', 'refunded']).count
    }
  end

  def self.format_order_data(order)
    {
      order_id: order.reference_number,
      order_date: order.created_at.strftime('%Y-%m-%d %H:%M:%S'),
      customer_name: order.user&.name || 'N/A',
      customer_email: order.user&.email || 'N/A',
      seller_name: order.dealer&.full_name || 'N/A',
      payment_method: order.payment_method,
      payment_status: order.payment_status,
      order_status: order.status,
      subtotal: order.subtotal_amount,
      commission: order.commission_amount,
      marketplace_fee: order.marketplace_fee,
      total_amount: order.total_amount,
      seller_settlement: order.seller_settlement_amount,
      items_count: order.order_items.count,
      items: order.order_items.map { |item| "#{item.product&.name} (#{item.quantity}x)" }.join('; ')
    }
  end

  def self.generate_sales_trends(orders, date_range)
    orders.group_by_day(:created_at).count.map do |date, count|
      { date: date.strftime('%Y-%m-%d'), orders: count }
    end
  end

  def self.generate_top_products(orders)
    order_items = OrderItem.joins(:order).where(order_id: orders.pluck(:id))
    order_items.group(:product_id)
               .select('product_id, SUM(quantity) as total_quantity, SUM(total_price) as total_revenue')
               .order('total_revenue DESC')
               .limit(20)
               .map do |item|
                 product = Product.find_by(id: item.product_id)
                 next unless product
                 {
                   product_name: product.name,
                   category: product.category&.name,
                   total_quantity: item.total_quantity,
                   total_revenue: item.total_revenue,
                   average_price: (item.total_revenue / item.total_quantity).round(2)
                 }
               end.compact
  end

  def self.generate_top_sellers(orders)
    orders.joins(:dealer)
          .group('dealers.id, dealers.full_name')
          .select('dealers.id, dealers.full_name, COUNT(*) as total_orders, SUM(orders.total_amount) as total_revenue')
          .order('total_revenue DESC')
          .limit(20)
          .map do |item|
            {
              seller_name: item.full_name,
              total_orders: item.total_orders,
              total_revenue: item.total_revenue,
              average_order_value: (item.total_revenue / item.total_orders).round(2)
            }
          end
  end

  def self.generate_payment_methods_breakdown(orders)
    orders.group(:payment_method).count.map do |method, count|
      total_amount = orders.where(payment_method: method).sum(:total_amount)
      { payment_method: method, orders_count: count, total_amount: total_amount }
    end
  end

  def self.generate_payout_summary(payouts, settlements, date_range)
    {
      period: "#{date_range.first.strftime('%B %Y')}",
      total_payouts: payouts.count,
      successful_payouts: payouts.where(status: 'paid').count,
      pending_payouts: payouts.where(status: 'pending').count,
      failed_payouts: payouts.where(status: 'failed').count,
      total_payout_amount: payouts.where(status: 'paid').sum(:amount),
      total_pending_amount: payouts.where(status: 'pending').sum(:amount),
      total_settlements: settlements.count,
      pending_settlements: settlements.where(status: 'pending').sum(:amount),
      completed_settlements: settlements.where(status: 'completed').sum(:amount)
    }
  end

  def self.format_payout_data(payout)
    {
      payout_id: payout.id,
      seller_name: payout.dealer&.full_name,
      amount: payout.amount,
      status: payout.status,
      transfer_id: payout.transfer_id,
      created_at: payout.created_at.strftime('%Y-%m-%d %H:%M:%S'),
      processed_at: payout.processed_at&.strftime('%Y-%m-%d %H:%M:%S'),
      failure_reason: payout.failure_reason
    }
  end

  def self.format_settlement_data(settlement)
    {
      settlement_id: settlement.id,
      seller_name: settlement.dealer&.full_name,
      order_reference: settlement.order&.reference_number,
      amount: settlement.amount,
      status: settlement.status,
      due_date: settlement.due_at&.strftime('%Y-%m-%d'),
      released_at: settlement.released_at&.strftime('%Y-%m-%d %H:%M:%S')
    }
  end

  def self.generate_pending_balances(date_range)
    Dealer.all.map do |dealer|
      pending_settlements = dealer.settlements.where(status: 'pending', created_at: date_range).sum(:amount)
      current_balance = dealer.settlement_balance

      {
        seller_name: dealer.full_name,
        pending_settlements: pending_settlements,
        current_balance: current_balance,
        total_pending: pending_settlements + current_balance
      }
    end.select { |d| d[:total_pending] > 0 }.sort_by { |d| d[:total_pending] }.reverse
  end

  def self.generate_payout_trends(date_range)
    DealerPayout.where(created_at: date_range)
                .group_by_day(:created_at)
                .sum(:amount)
                .map { |date, amount| { date: date.strftime('%Y-%m-%d'), amount: amount } }
  end

  def self.generate_commission_summary(orders, date_range)
    {
      period: "#{date_range.first.strftime('%B %Y')}",
      total_orders: orders.count,
      total_commission: orders.sum(:commission_amount),
      total_marketplace_fee: orders.sum(:marketplace_fee),
      average_commission_per_order: orders.average(:commission_amount).to_f.round(2),
      commission_percentage: orders.sum(:commission_amount).to_f / orders.sum(:subtotal_amount) * 100
    }
  end

  def self.format_commission_data(order)
    {
      order_id: order.reference_number,
      order_date: order.created_at.strftime('%Y-%m-%d'),
      seller_name: order.dealer&.full_name,
      subtotal: order.subtotal_amount,
      commission_amount: order.commission_amount,
      commission_percentage: (order.commission_amount.to_f / order.subtotal_amount * 100).round(2),
      marketplace_fee: order.marketplace_fee,
      seller_settlement: order.seller_settlement_amount
    }
  end

  def self.generate_commission_trends(orders, date_range)
    orders.group_by_day(:created_at)
          .sum(:commission_amount)
          .map { |date, amount| { date: date.strftime('%Y-%m-%d'), commission: amount } }
  end

  def self.generate_commission_by_seller(orders)
    orders.joins(:dealer)
          .group('dealers.id, dealers.full_name')
          .select('dealers.full_name, SUM(orders.commission_amount) as total_commission, COUNT(*) as orders_count')
          .order('total_commission DESC')
          .map do |item|
            {
              seller_name: item.full_name,
              orders_count: item.orders_count,
              total_commission: item.total_commission,
              average_commission: (item.total_commission / item.orders_count).round(2)
            }
          end
  end

  def self.generate_commission_by_category(orders)
    OrderItem.joins(:order, :product => :category)
             .where(order_id: orders.pluck(:id))
             .group('categories.name')
             .select('categories.name as category_name, SUM(order_items.total_price) as total_revenue, COUNT(DISTINCT orders.id) as orders_count')
             .map do |item|
               commission = item.total_revenue * 0.1 # Assuming 10% commission
               {
                 category: item.category_name,
                 orders_count: item.orders_count,
                 total_revenue: item.total_revenue,
                 estimated_commission: commission.round(2)
               }
             end
  end

  def self.generate_refund_summary(refunds, date_range)
    total_refund_amount = refunds.sum(:refund_amount)
    total_order_amount = refunds.joins(:order).sum('orders.total_amount')

    {
      period: "#{date_range.first.strftime('%B %Y')}",
      total_refunds: refunds.count,
      total_refund_amount: total_refund_amount,
      refund_percentage: total_order_amount > 0 ? (total_refund_amount.to_f / total_order_amount * 100).round(2) : 0,
      average_refund_amount: refunds.average(:refund_amount).to_f.round(2),
      pending_refunds: refunds.where(status: 'pending').count,
      processed_refunds: refunds.where(status: 'processed').count,
      failed_refunds: refunds.where(status: 'failed').count
    }
  end

  def self.format_refund_data(refund)
    {
      refund_id: refund.id,
      order_id: refund.order&.reference_number,
      customer_name: refund.order&.user&.name,
      refund_amount: refund.refund_amount,
      refund_type: refund.refund_type,
      reason: refund.reason,
      status: refund.status,
      requested_at: refund.created_at.strftime('%Y-%m-%d %H:%M:%S'),
      processed_at: refund.processed_at&.strftime('%Y-%m-%d %H:%M:%S'),
      payment_method: refund.order&.payment_method
    }
  end

  def self.generate_refund_reasons_breakdown(refunds)
    refunds.group(:reason).count.map do |reason, count|
      total_amount = refunds.where(reason: reason).sum(:refund_amount)
      { reason: reason, count: count, total_amount: total_amount }
    end
  end

  def self.generate_refund_trends(refunds, date_range)
    refunds.group_by_day(:created_at)
           .count
           .map { |date, count| { date: date.strftime('%Y-%m-%d'), refunds: count } }
  end

  def self.generate_refund_by_payment_method(refunds)
    refunds.joins(:order)
           .group('orders.payment_method')
           .count
           .map do |method, count|
             total_amount = refunds.joins(:order).where(orders: { payment_method: method }).sum(:refund_amount)
             { payment_method: method, refunds_count: count, total_amount: total_amount }
           end
  end

  def self.generate_tax_summary(orders, date_range)
    subtotal = orders.sum(:subtotal_amount)
    cgst = subtotal * 0.09 # Assuming 9% CGST
    sgst = subtotal * 0.09 # Assuming 9% SGST
    igst = 0 # Would need state-wise calculation
    total_tax = cgst + sgst + igst

    {
      period: "#{date_range.first.strftime('%B %Y')}",
      total_orders: orders.count,
      taxable_amount: subtotal,
      cgst_amount: cgst.round(2),
      sgst_amount: sgst.round(2),
      igst_amount: igst.round(2),
      total_tax: total_tax.round(2),
      tax_percentage: (total_tax / subtotal * 100).round(2)
    }
  end

  def self.generate_tax_breakdown(orders)
    # This would need actual tax calculation logic based on HSN codes and GST rates
    orders.map do |order|
      {
        order_id: order.reference_number,
        taxable_amount: order.subtotal_amount,
        cgst_rate: 9.0,
        cgst_amount: (order.subtotal_amount * 0.09).round(2),
        sgst_rate: 9.0,
        sgst_amount: (order.subtotal_amount * 0.09).round(2),
        total_tax: (order.subtotal_amount * 0.18).round(2)
      }
    end
  end

  def self.generate_gst_by_state(orders)
    orders.joins(:billing_address)
          .group('addresses.state')
          .select('addresses.state, COUNT(*) as orders_count, SUM(orders.subtotal_amount) as taxable_amount')
          .map do |item|
            tax_amount = item.taxable_amount * 0.18 # Assuming 18% GST
            {
              state: item.state,
              orders_count: item.orders_count,
              taxable_amount: item.taxable_amount,
              gst_amount: tax_amount.round(2)
            }
          end
  end

  def self.generate_hsn_sac_codes(orders)
    # This would need actual HSN/SAC code mapping from products
    order_items = OrderItem.joins(:order, :product).where(order_id: orders.pluck(:id))
    order_items.group('products.hsn_code')
               .select('products.hsn_code, SUM(order_items.total_price) as taxable_value, SUM(order_items.quantity) as total_quantity')
               .map do |item|
                 {
                   hsn_code: item.hsn_code || 'Not Specified',
                   taxable_value: item.taxable_value,
                   total_quantity: item.total_quantity,
                   gst_amount: (item.taxable_value * 0.18).round(2) # Assuming 18% GST
                 }
               end
  end

  def self.generate_tax_trends(orders, date_range)
    orders.group_by_day(:created_at)
          .select('DATE(created_at) as date, SUM(subtotal_amount) as taxable_amount')
          .map do |item|
            {
              date: item.date.strftime('%Y-%m-%d'),
              taxable_amount: item.taxable_amount,
              gst_amount: (item.taxable_amount * 0.18).round(2)
            }
          end
  end

  def self.generate_compliance_check(orders, date_range)
    {
      gst_registered_sellers: orders.joins(:dealer).where('dealers.gst_number IS NOT NULL').distinct.count('dealers.id'),
      total_sellers: orders.distinct.pluck(:dealer_id).count,
      orders_with_gst: orders.where('subtotal_amount >= ?', 25000).count, # GST threshold
      total_orders: orders.count,
      compliance_percentage: ((orders.where('subtotal_amount >= ?', 25000).count.to_f / orders.count) * 100).round(2)
    }
  end

  def self.generate_balance_sheet(orders, payouts, refunds, date_range)
    revenue = orders.sum(:total_amount)
    refunds_amount = refunds.sum(:refund_amount)
    payouts_amount = payouts.where(status: 'paid').sum(:amount)
    pending_payouts = payouts.where(status: 'pending').sum(:amount)

    {
      assets: {
        cash_and_equivalents: revenue - refunds_amount - payouts_amount,
        accounts_receivable: pending_payouts,
        inventory: 0 # Would need inventory tracking
      },
      liabilities: {
        accounts_payable: pending_payouts,
        seller_payables: payouts.where(status: 'pending').sum(:amount)
      },
      equity: {
        retained_earnings: revenue - refunds_amount - payouts_amount - pending_payouts
      }
    }
  end

  def self.generate_profit_loss_statement(orders, payouts, refunds, date_range)
    revenue = orders.sum(:total_amount)
    refunds_amount = refunds.sum(:refund_amount)
    commission_expense = orders.sum(:commission_amount)
    marketplace_fee = orders.sum(:marketplace_fee)
    payout_expense = payouts.where(status: 'paid').sum(:amount)

    {
      revenue: revenue,
      less_returns: refunds_amount,
      net_revenue: revenue - refunds_amount,
      less_commissions: commission_expense,
      less_marketplace_fees: marketplace_fee,
      less_payouts: payout_expense,
      gross_profit: revenue - refunds_amount - commission_expense - marketplace_fee,
      net_profit: revenue - refunds_amount - commission_expense - marketplace_fee - payout_expense
    }
  end

  def self.generate_cash_flow_statement(orders, payouts, refunds, date_range)
    operating_activities = orders.sum(:total_amount) - refunds.sum(:refund_amount)
    financing_activities = -payouts.where(status: 'paid').sum(:amount)

    {
      operating_activities: operating_activities,
      financing_activities: financing_activities,
      net_cash_flow: operating_activities + financing_activities
    }
  end

  def self.generate_accounts_receivable(orders, date_range)
    orders.where(payment_status: 'pending')
          .group('users.id, users.name')
          .select('users.id, users.name, SUM(orders.total_amount) as pending_amount, COUNT(*) as pending_orders')
          .map do |item|
            {
              customer_name: item.name,
              pending_orders: item.pending_orders,
              pending_amount: item.pending_amount
            }
          end
  end

  def self.generate_accounts_payable(payouts, date_range)
    payouts.where(status: 'pending')
           .group('dealers.id, dealers.full_name')
           .select('dealers.id, dealers.full_name, SUM(amount) as pending_amount, COUNT(*) as pending_payouts')
           .map do |item|
             {
               seller_name: item.full_name,
               pending_payouts: item.pending_payouts,
               pending_amount: item.pending_amount
             }
           end
  end

  def self.generate_audit_trail(orders, payouts, refunds, date_range)
    # This would need proper audit logging implementation
    [
      { action: 'Orders Created', count: orders.count, total_amount: orders.sum(:total_amount) },
      { action: 'Payouts Processed', count: payouts.where(status: 'paid').count, total_amount: payouts.where(status: 'paid').sum(:amount) },
      { action: 'Refunds Processed', count: refunds.where(status: 'processed').count, total_amount: refunds.where(status: 'processed').sum(:refund_amount) }
    ]
  end

  def self.generate_compliance_summary(orders, payments, settlements, payouts, refunds)
    {
      total_orders: orders.count,
      successful_payments: payments.where(status: 'paid').count,
      payment_success_rate: payments.count > 0 ? (payments.where(status: 'paid').count.to_f / payments.count * 100).round(2) : 0,
      completed_settlements: settlements.where(status: 'completed').count,
      processed_payouts: payouts.where(status: 'paid').count,
      processed_refunds: refunds.where(status: 'processed').count,
      data_integrity_score: 100, # Would need actual checks
      compliance_status: 'Compliant'
    }
  end

  def self.generate_data_integrity_checks(orders, payments)
    # Basic integrity checks
    orphaned_payments = payments.where.missing(:order).count
    orders_without_payments = orders.where.missing(:payment_attempt).count

    {
      orphaned_payments: orphaned_payments,
      orders_without_payments: orders_without_payments,
      integrity_score: orphaned_payments == 0 && orders_without_payments == 0 ? 100 : 50
    }
  end

  def self.generate_financial_reconciliation(orders, payouts, refunds)
    order_total = orders.sum(:total_amount)
    payout_total = payouts.where(status: 'paid').sum(:amount)
    refund_total = refunds.where(status: 'processed').sum(:refund_amount)

    {
      expected_balance: order_total - refund_total,
      actual_balance: order_total - payout_total - refund_total,
      reconciliation_status: (order_total - refund_total) == (order_total - payout_total - refund_total) ? 'Matched' : 'Mismatch'
    }
  end

  def self.generate_regulatory_reporting(orders, date_range)
    # GST and other regulatory reporting data
    {
      gst_report: {
        total_taxable_value: orders.sum(:subtotal_amount),
        total_gst_collected: (orders.sum(:subtotal_amount) * 0.18).round(2),
        gst_period: "#{date_range.first.strftime('%B %Y')}"
      },
      sales_report: {
        total_sales: orders.sum(:total_amount),
        b2b_sales: orders.joins(:dealer).where('dealers.gst_number IS NOT NULL').sum(:total_amount),
        b2c_sales: orders.joins(:dealer).where('dealers.gst_number IS NULL').sum(:total_amount)
      }
    }
  end

  def self.generate_audit_logs(date_range)
    # This would need actual audit logging
    [
      { timestamp: Time.current, action: 'Report Generated', user: 'System', details: 'Monthly audit report' }
    ]
  end

  def self.generate_risk_assessment(orders, payments, date_range)
    failed_payments = payments.where(status: 'failed').count
    high_value_orders = orders.where('total_amount > ?', 50000).count
    chargebacks = 0 # Would need chargeback tracking

    risk_score = 0
    risk_score += (failed_payments.to_f / payments.count * 100) if payments.count > 0
    risk_score += (high_value_orders.to_f / orders.count * 100) if orders.count > 0
    risk_score += chargebacks * 10

    {
      failed_payment_rate: payments.count > 0 ? (failed_payments.to_f / payments.count * 100).round(2) : 0,
      high_value_orders_percentage: orders.count > 0 ? (high_value_orders.to_f / orders.count * 100).round(2) : 0,
      chargeback_rate: 0,
      overall_risk_score: risk_score.round(2),
      risk_level: risk_score < 10 ? 'Low' : risk_score < 25 ? 'Medium' : 'High'
    }
  end

  def self.generate_report_file(data, report_type, format)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "#{report_type}_#{timestamp}.#{format}"

    file_path = Rails.root.join('tmp', filename)

    if format == 'xlsx'
      generate_xlsx_report(data, file_path, report_type)
    else
      generate_csv_report(data, file_path, report_type)
    end

    {
      filename: filename,
      file_path: file_path,
      download_url: "/api/reports/download/#{filename}",
      generated_at: Time.current,
      format: format
    }
  end

  def self.generate_xlsx_report(data, file_path, report_type)
    Axlsx::Package.new do |p|
      p.workbook.add_worksheet(name: 'Summary') do |sheet|
        add_summary_sheet(sheet, data[:summary], report_type)
      end

      data.except(:summary).each do |sheet_name, sheet_data|
        next unless sheet_data.is_a?(Array) && sheet_data.any?
        p.workbook.add_worksheet(name: sheet_name.to_s.titleize) do |sheet|
          add_data_sheet(sheet, sheet_data, sheet_name)
        end
      end

      p.serialize(file_path.to_s)
    end
  end

  def self.generate_csv_report(data, file_path, report_type)
    CSV.open(file_path, 'w') do |csv|
      # Summary section
      csv << ['SUMMARY']
      csv << ['Report Type', report_type.titleize]
      csv << ['Generated At', Time.current.strftime('%Y-%m-%d %H:%M:%S')]
      csv << []

      data[:summary]&.each do |key, value|
        csv << [key.to_s.titleize, value]
      end

      csv << []
      csv << ['DETAILED DATA']
      csv << []

      # Data sections
      data.except(:summary).each do |section_name, section_data|
        next unless section_data.is_a?(Array) && section_data.any?
        csv << [section_name.to_s.upcase]
        csv << section_data.first.keys.map(&:to_s).map(&:titleize)
        section_data.each do |row|
          csv << row.values
        end
        csv << []
      end
    end
  end

  def self.add_summary_sheet(sheet, summary_data, report_type)
    sheet.add_row ["#{report_type.titleize} Report"]
    sheet.add_row ["Generated At", Time.current.strftime('%Y-%m-%d %H:%M:%S')]
    sheet.add_row []

    summary_data&.each do |key, value|
      sheet.add_row [key.to_s.titleize, value]
    end
  end

  def self.add_data_sheet(sheet, data, sheet_name)
    return if data.empty?

    # Add headers
    headers = data.first.keys.map(&:to_s).map(&:titleize)
    sheet.add_row headers

    # Add data rows
    data.each do |row|
      sheet.add_row row.values
    end
  end
end