class Role < ApplicationRecord
  belongs_to :created_by, class_name: "AdminUser"
  has_many :admin_roles, dependent: :destroy
  has_many :admin_users, through: :admin_roles

  serialize :module_access, type: Array, coder: YAML
  serialize :module_permissions, type: Hash, coder: YAML

  validates :name, presence: true, uniqueness: true

  validate :validate_module_access
  validate :validate_module_permissions

  ALLOWED_MODULES = %w[ accounts addresses admin_users roles brands categories cat_filters contact_us dealers dealer_locations dealer_profiles dealer_products products product_specifications product_variants reviews notifications orders analytics coupons settings ]
  ALLOWED_PERMISSIONS = %w[read write]

  def validate_module_access
    invalid = module_access - ALLOWED_MODULES
    errors.add(:module_access, "Invalid modules") if invalid.any?
  end

  def validate_module_permissions
    return if module_permissions.blank?
    unless module_permissions.is_a?(Array)
      errors.add(:module_permissions, "must be an array")
      return
    end
    module_permissions.each do |mod, perms|
      unless ALLOWED_MODULES.include?(mod)
        errors.add(:module_permissions, "contains invalid module #{mod}")
      end
      unless perms.is_a?(Array) && perms.all? { |p| ALLOWED_PERMISSIONS.include?(p) }
        errors.add(:module_permissions, "permissions for #{mod} must be array of read/write")
      end
    end
  end
end
