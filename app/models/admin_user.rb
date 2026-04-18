class AdminUser < ApplicationRecord
  has_secure_password validations: false
  attr_accessor :generated_password

  has_many :admin_roles, dependent: :destroy
  has_many :roles, through: :admin_roles
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :admin_deletion_requests, foreign_key: :admin_user_id, dependent: :destroy, inverse_of: :admin_user
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy

  enum :status, { active: 'active', inactive: 'inactive' }

  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, uniqueness: true, allow_nil: true

  before_create :generate_password

  def super_admin?
    is_super_admin
  end

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  def can_access?(module_name, permission = :read)
    return true if super_admin?

    normalized_module = module_name.to_s
    required_permission = permission.to_s

    roles.active.any? do |role|
      permissions = role.permissions_for(normalized_module)
      permissions.include?(required_permission)
    end
  end

  private

  def generate_password
    return if password.present?

    year = Time.current.year.to_s
    email_part = email.split('@').first.to_s[0, 3]
    email_part = email_part.ljust(3, "x")
    generated_password = "#{email_part}@#{year}"
    self.generated_password = generated_password
    self.password = generated_password
    self.password_confirmation = generated_password
  end
end
