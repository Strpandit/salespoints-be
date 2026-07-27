class RetailOrderMailer < ApplicationMailer
  def admin_order_placed(order_id)
    @order = load_order(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer
    @subject_line = "New Order Placed - #{@order.order_number}"

    mail_to_admins(subject: @subject_line)
  end

  def order_accepted(order_id, recipient_type)
    @order = load_order(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer

    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?

      @subject_line = "Order Accepted - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    when "seller"
      return if @seller&.email.blank?

      @subject_line = "Order Accepted - #{@order.order_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
    when "admin"
      @subject_line = "Order Accepted - #{@order.order_number}"
      @view_type = "admin"
      mail_to_admins(subject: @subject_line)
    end
  end

  def order_shipped(order_id)
    @order = load_order(order_id)
    @buyer = @order.buyer
    return if @buyer&.email.blank?

    @subject_line = "Order Shipped - #{@order.order_number}"
    mail(to: @buyer.email, subject: @subject_line)
  end

  def order_delivered(order_id, recipient_type)
    @order = load_order(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer

    attachments["Invoice_#{@order.order_number}.pdf"] = {
      mime_type: "application/pdf",
      content: InvoicePdf.new(@order).generate
    }

    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?

      @subject_line = "Order Delivered - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    when "seller"
      return if @seller&.email.blank?

      @subject_line = "Order Delivered - #{@order.order_number}"
      @view_type = "seller"
      mail(to: @seller.email, subject: @subject_line)
    when "admin"
      @subject_line = "Order Delivered - #{@order.order_number}"
      @view_type = "admin"
      mail_to_admins(subject: @subject_line)
    end
  end

  def order_terminated(order_id, recipient_type, reason)
    @order = load_order(order_id)
    @buyer = @order.buyer
    @seller = @order.seller_dealer
    @reason = reason.to_s.humanize

    case recipient_type.to_s
    when "buyer"
      return if @buyer&.email.blank?

      @subject_line = "Order #{@reason} - #{@order.order_number}"
      @view_type = "buyer"
      mail(to: @buyer.email, subject: @subject_line)
    when "admin"
      @subject_line = "Order #{@reason} - #{@order.order_number}"
      @view_type = "admin"
      mail_to_admins(subject: @subject_line)
    end
  end

  private

  def load_order(order_id)
    Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product }).find(order_id)
  end

  def mail_to_admins(subject:)
    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    return if admin_emails.empty?

    mail(to: admin_emails.first, bcc: admin_emails.drop(1), subject: subject)
  end
end
