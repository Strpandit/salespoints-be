class EmailDispatcherService
  # B2C / Wholesaler (Retail) Emails
  def self.retail_order_placed(order)
    RetailOrderMailer.admin_order_placed(order.id).deliver_later
  end
  
  def self.retail_order_accepted(order)
    RetailOrderMailer.order_accepted(order.id, "buyer").deliver_later
    RetailOrderMailer.order_accepted(order.id, "seller").deliver_later
    RetailOrderMailer.order_accepted(order.id, "admin").deliver_later
  end
  
  def self.retail_order_shipped(order)
    RetailOrderMailer.order_shipped(order.id).deliver_later
  end
  
  def self.retail_order_delivered(order)
    RetailOrderMailer.order_delivered(order.id, "buyer").deliver_later
    RetailOrderMailer.order_delivered(order.id, "seller").deliver_later
    RetailOrderMailer.order_delivered(order.id, "admin").deliver_later
  end
  
  def self.retail_order_terminated(order, reason)
    RetailOrderMailer.order_terminated(order.id, reason).deliver_later
  end
  
  # B2B Emails
  def self.b2b_request_placed(order)
    B2bOrderMailer.admin_request_placed(order.id).deliver_later
  end
  
  def self.b2b_request_accepted(order)
    B2bOrderMailer.request_accepted(order.id, "buyer").deliver_later
    B2bOrderMailer.request_accepted(order.id, "seller").deliver_later
    B2bOrderMailer.request_accepted(order.id, "admin").deliver_later
  end
  
  def self.b2b_payment_done(order)
    B2bOrderMailer.payment_done(order.id, "buyer").deliver_later
    B2bOrderMailer.payment_done(order.id, "seller").deliver_later
    B2bOrderMailer.payment_done(order.id, "admin").deliver_later
  end
  
  def self.b2b_order_shipped(order)
    B2bOrderMailer.order_shipped(order.id).deliver_later
  end
  
  def self.b2b_order_delivered(order)
    B2bOrderMailer.order_delivered(order.id, "buyer").deliver_later
    B2bOrderMailer.order_delivered(order.id, "seller").deliver_later
    B2bOrderMailer.order_delivered(order.id, "admin").deliver_later
  end
  
  def self.b2b_order_terminated(order, reason)
    B2bOrderMailer.order_terminated(order.id, reason).deliver_later
  end
end