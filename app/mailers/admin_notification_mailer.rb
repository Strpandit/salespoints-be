class AdminNotificationMailer < ApplicationMailer
  def entity_created(admin_email, entity_type, entity_name, actor, details = {})
    @entity_type = entity_type
    @entity_name = entity_name
    @actor       = normalize_actor(actor)
    @details     = details
    mail(
      to:      admin_email,
      subject: "🆕 [SalesPoints] New #{entity_type} Created – #{entity_name}"
    )
  end

  def entity_updated(admin_email, entity_type, entity_name, actor, changes = {})
    @entity_type = entity_type
    @entity_name = entity_name
    @actor       = normalize_actor(actor)
    @changes     = changes
    mail(
      to:      admin_email,
      subject: "✏️ [SalesPoints] #{entity_type} Updated – #{entity_name}"
    )
  end

  def entity_deleted(admin_email, entity_type, entity_name, actor, details = {})
    @entity_type = entity_type
    @entity_name = entity_name
    @actor       = normalize_actor(actor)
    @details     = details
    mail(
      to:      admin_email,
      subject: "🗑️ [SalesPoints] #{entity_type} Deleted – #{entity_name}"
    )
  end

  def dealer_action(admin_email, dealer_name, action, actor, changes = {}, details = nil)
    @dealer_name = dealer_name
    @action      = action
    @actor       = normalize_actor(actor)
    @changes     = changes
    @details     = details
    mail(
      to:      admin_email,
      subject: "📋 [SalesPoints] Dealer #{action.to_s.titleize} – #{dealer_name}"
    )
  end

  def dealer_reverification_requested(admin_email, dealer, changes = {})
    @dealer  = dealer
    @changes = changes
    mail(
      to:      admin_email,
      subject: "⚠️ [SalesPoints] Dealer Profile Re-Verification Required – #{dealer.full_name}"
    )
  end

  def product_action(admin_email, product_name, action, dealer_name, actor, changes = {}, details = nil)
    @product_name = product_name
    @action       = action
    @dealer_name  = dealer_name
    @actor        = normalize_actor(actor)
    @changes      = changes
    @details      = details
    mail(
      to:      admin_email,
      subject: "📦 [SalesPoints] Product #{action.to_s.titleize} – #{product_name}"
    )
  end

  private

  def normalize_actor(actor)
    case actor
    when Hash
      {
        name:  actor[:name] || actor["name"] || actor[:email] || actor["email"] || "System Admin",
        email: actor[:email] || actor["email"] || ""
      }
    when String
      {
        name:  actor.presence || "System Admin",
        email: actor.presence || ""
      }
    when NilClass
      { name: "System Admin", email: "" }
    else
      name  = actor.respond_to?(:full_name) ? actor.full_name : (actor.respond_to?(:name) ? actor.name : nil)
      name  ||= actor.respond_to?(:first_name) ? "#{actor.first_name} #{actor.try(:last_name)}".strip : nil
      email = actor.respond_to?(:email) ? actor.email : ""
      name  = email if name.blank?
      {
        name:  name.presence || "System Admin",
        email: email.to_s
      }
    end
  end
end
