class AdminNotificationMailer < ApplicationMailer
  def entity_created(admin_email, entity_type, entity_name, created_by)
    @entity_type = entity_type
    @entity_name = entity_name
    @created_by = created_by
    mail(to: admin_email, subject: "🆕 New #{entity_type} Created: #{entity_name}")
  end

  def entity_updated(admin_email, entity_type, entity_name, updated_by)
    @entity_type = entity_type
    @entity_name = entity_name
    @updated_by = updated_by
    mail(to: admin_email, subject: "✏️ #{entity_type} Updated: #{entity_name}")
  end

  def entity_deleted(admin_email, entity_type, entity_name, deleted_by)
    @entity_type = entity_type
    @entity_name = entity_name
    @deleted_by = deleted_by
    mail(to: admin_email, subject: "🗑️ #{entity_type} Deleted: #{entity_name}")
  end

  def dealer_action(admin_email, dealer_name, action, details = nil)
    @dealer_name = dealer_name
    @action = action
    @details = details
    mail(to: admin_email, subject: "📋 Dealer Action: #{action} - #{dealer_name}")
  end

  def product_action(admin_email, product_name, action, dealer_name, details = nil)
    @product_name = product_name
    @action = action
    @dealer_name = dealer_name
    @details = details
    mail(to: admin_email, subject: "📦 Dealer Product #{action}: #{product_name}")
  end
end
