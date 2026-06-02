class Role < ApplicationRecord
  belongs_to :created_by, class_name: "AdminUser"
  has_many :admin_roles, dependent: :destroy
  has_many :admin_users, through: :admin_roles

  serialize :module_access, type: Array, coder: YAML
  serialize :module_permissions, type: Hash, coder: YAML

  scope :active, -> { where(is_active: true) }

  before_validation :normalize_serialized_permissions

  validates :name, presence: true, uniqueness: true

  validate :validate_module_access
  validate :validate_module_permissions

  ALLOWED_MODULES = %w[ accounts account_deletion_requests admin_deletion_requests admin_users roles brands categories cat_filters dealers dealer_locations dealer_profiles dealer_products products reviews notifications orders analytics coupons settings dealer_deletion_requests wholesaler_posts ]
  ALLOWED_PERMISSIONS = %w[read write]

  def validate_module_access
    invalid = module_access - ALLOWED_MODULES
    errors.add(:module_access, "Invalid modules") if invalid.any?
  end

  def validate_module_permissions
    return if module_permissions.blank?
    unless module_permissions.is_a?(Hash)
      errors.add(:module_permissions, "must be a hash")
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

  def permissions_for(module_name)
    normalized_module = module_name.to_s
    return [] unless ALLOWED_MODULES.include?(normalized_module)

    direct_permissions =
      if module_permissions.is_a?(Hash)
        Array(module_permissions[normalized_module] || module_permissions[normalized_module.to_sym])
      else
        []
      end
    normalized_permissions = direct_permissions.map(&:to_s).select { |perm| ALLOWED_PERMISSIONS.include?(perm) }.uniq

    if normalized_permissions.empty? && Array(module_access).include?(normalized_module)
      return ALLOWED_PERMISSIONS.dup
    end

    normalized_permissions
  end

  private

  def normalize_serialized_permissions
    self.module_access = normalize_module_access_value(module_access)
    self.module_permissions = normalize_module_permissions_value(module_permissions)
  end

  def normalize_module_access_value(value)
    parsed = value.is_a?(String) ? deserialize_legacy_value(value) : value
    Array(parsed).map(&:to_s).select { |mod| ALLOWED_MODULES.include?(mod) }.uniq
  end

  def normalize_module_permissions_value(value)
    parsed = value.is_a?(String) ? deserialize_legacy_value(value) : value
    return {} unless parsed.is_a?(Hash)

    parsed.each_with_object({}) do |(module_name, permissions), acc|
      normalized_module = module_name.to_s
      next unless ALLOWED_MODULES.include?(normalized_module)

      normalized_permissions = Array(permissions).map(&:to_s).select { |perm| ALLOWED_PERMISSIONS.include?(perm) }.uniq
      acc[normalized_module] = normalized_permissions if normalized_permissions.any?
    end
  end

  def deserialize_legacy_value(value)
    stripped = value.to_s.strip
    return {} if stripped.blank? || stripped == "--- {}" || stripped == "{}"
    return [] if stripped == "--- []" || stripped == "[]"

    YAML.safe_load(stripped, permitted_classes: [], aliases: false)
  rescue Psych::SyntaxError
    JSON.parse(stripped)
  rescue JSON::ParserError, TypeError
    value
  end
end
