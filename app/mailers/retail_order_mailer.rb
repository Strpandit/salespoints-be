class RetailOrderMailer < ApplicationMailer
  # ORDER PLACED - Super Admin Only
  def admin_order_placed(order_id)
    @order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                  .find(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer
    
    @subject_line = "🔔 New Order Placed - #{@order.order_number}"
    
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    return if admin_emails.empty?
    
    mail(
      to: admin_emails.first,
      bcc: admin_emails.drop(1),
      subject: @subject_line
    )
  end
  
  # ORDER ACCEPTED - Buyer, Seller, Admin
  def order_accepted(order_id, recipient_type)
    @order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                  .find(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer
    
    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?
      @subject_line = "✅ Order Accepted - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
      
    when "seller"
      return if @seller&.email.blank?
      @subject_line = "✅ Order Accepted - #{@order.order_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
      
    when "admin"
      admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
      return if admin_emails.empty?
      @subject_line = "✅ Order Accepted - #{@order.order_number}"
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
    @order = Order.includes(:buyer, order_items: { product_variant: :product })
                  .find(order_id)
    @buyer = @order.buyer
    return if @buyer&.email.blank?
    
    @subject_line = "🚚 Order Shipped - #{@order.order_number}"
    mail(to: @buyer.email, subject: @subject_line)
  end
  
  # ORDER DELIVERED - Buyer, Seller, Admin (with Invoice PDF)
  def order_delivered(order_id, recipient_type)
    @order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                  .find(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer
    
    # Generate PDF invoice
    attachments["Invoice_#{@order.order_number}.pdf"] = {
      mime_type: "application/pdf",
      content: InvoicePdfGenerator.new(@order).generate
    }
    
    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?
      @subject_line = "📦 Order Delivered - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
      
    when "seller"
      return if @seller&.email.blank?
      @subject_line = "📦 Order Delivered - #{@order.order_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
      
    when "admin"
      admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
      return if admin_emails.empty?
      @subject_line = "📦 Order Delivered - #{@order.order_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
  
  # ORDER CANCELLED/REJECTED/EXPIRED - Buyer & Admin
  def order_terminated(order_id, reason)
    @order = Order.includes(:buyer, order_items: { product_variant: :product })
                  .find(order_id)
    @buyer = @order.buyer
    @reason = reason.to_s.humanize
    
    # Buyer email
    if @buyer&.email.present?
      @subject_line = "❌ Order #{@reason} - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    end
    
    # Admin email
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    if admin_emails.any?
      @subject_line = "❌ Order #{@reason} - #{@order.order_number}"
      @view_type = "admin"
      mail(
        to: admin_emails.first,
        bcc: admin_emails.drop(1),
        subject: @subject_line
      )
    end
  end
end