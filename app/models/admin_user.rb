class AdminUser < ApplicationRecord
  has_secure_password validations: false

  has_many :admin_roles, dependent: :destroy
  has_many :roles, through: :admin_roles

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

  def can_access?(module_name)
    return true if super_admin?
    roles.any? do |role|
      role.module_access.include?(module_name.to_s)
    end
  end

  private

  def generate_password
    return if password.present?

    year = Time.current.year.to_s
    email_part = email.split('@').first.to_s[0, 3]
    email_part = email_part.ljust(3, "x")
    generated_password = "#{email_part}@#{year}"
    self.password = generated_password
    self.password_confirmation = generated_password
  end
end