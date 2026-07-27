class B2bOrderMailer < ApplicationMailer
  # REQUEST PLACED - Super Admin Only
  def admin_request_placed(order_id)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    
    @subject_line = "🔔 New B2B Request - #{@order.reference_number}"
    
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    return if admin_emails.empty?
    
    mail(
      to: admin_emails.first,
      bcc: admin_emails.drop(1),
      subject: @subject_line
    )
  end

  # ORDER CREATED (Final Order) - Buyer, Seller, Admin
  def order_created(order_id)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    @seller = @order.seller_dealer
    
    # Buyer
    if @buyer&.email.present?
      @subject_line = "✅ Order Created - #{@order.reference_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    end
    
    # Seller
    if @seller&.email.present?
      @subject_line = "✅ Order Created - #{@order.reference_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
    end
    
    # Admin
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    if admin_emails.any?
      @subject_line = "✅ Order Created - #{@order.reference_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  # REQUEST ACCEPTED (Payment Pending) - Buyer, Seller, Admin
  def request_accepted(order_id, recipient_type)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    @seller = @order.seller_dealer
    
    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?
      @subject_line = "✅ Request Accepted - Payment Pending"
      @view_type = "buyer"
      @payment_link = generate_payment_link(@order)
      mail(to: @buyer.email, subject: @subject_line)
      
    when "seller"
      return if @seller&.email.blank?
      @subject_line = "✅ Request Accepted - #{@order.reference_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
      
    when "admin"
      admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
      return if admin_emails.empty?
      @subject_line = "✅ Request Accepted - #{@order.reference_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  # PAYMENT DONE - Buyer, Seller, Admin
  def payment_done(order_id, recipient_type)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    @seller = @order.seller_dealer
    @seller_dealer = @seller
    @buyer_dealer = @buyer
    @payment = {
      method: payment_method_label(@order.payment_method),
      reference: @order.payment_reference || @order.gateway_order_reference,
      paid_at: @order.paid_at || @order.payment_confirmed_at,
      amount: @order.total_amount
    }
    
    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?
      @subject_line = "💳 Payment Confirmed - #{@order.reference_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
      
    when "seller"
      return if @seller&.email.blank?
      @subject_line = "💳 Payment Confirmed - #{@order.reference_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
      
    when "admin"
      admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
      return if admin_emails.empty?
      @subject_line = "💳 Payment Confirmed - #{@order.reference_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  # ORDER SHIPPED - Buyer Only
  def order_shipped(order_id)
    @order = B2bOrder.includes(:buyer_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    return if @buyer&.email.blank?
    
    @subject_line = "🚚 Order Shipped - #{@order.reference_number}"
    mail(to: @buyer.email, subject: @subject_line)
  end
  
  # ORDER DELIVERED - Buyer, Seller, Admin (with Invoice PDF)
  def order_delivered(order_id, recipient_type)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    @seller = @order.seller_dealer
    
    # Generate PDF invoice
    attachments["Invoice_#{@order.reference_number}.pdf"] = {
      mime_type: "application/pdf",
      content: InvoicePdfGenerator.new(@order).generate
    }
    
    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?
      @subject_line = "📦 Order Delivered - #{@order.reference_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
      
    when "seller"
      return if @seller&.email.blank?
      @subject_line = "📦 Order Delivered - #{@order.reference_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
      
    when "admin"
      admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
      return if admin_emails.empty?
      @subject_line = "📦 Order Delivered - #{@order.reference_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  # ORDER TERMINATED (Expired/Cancelled/Rejected) - Buyer & Admin
  def order_terminated(order_id, reason)
    @order = B2bOrder.includes(:buyer_dealer, b2b_order_items: { product_variant: :product })
                      .find(order_id)
    @buyer = @order.buyer_dealer
    @reason = reason.to_s.humanize
    
    # Buyer email
    if @buyer&.email.present?
      @subject_line = "❌ Request #{@reason} - #{@order.reference_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    end
    
    # Admin email
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    if admin_emails.any?
      @subject_line = "❌ Request #{@reason} - #{@order.reference_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  private
  
  def generate_payment_link(order)
    base = ENV["FRONTEND_URL"].to_s.presence || "https://salespoints.in"
    "#{base}/b2b/payment/#{order.payment_token}"
  end
end