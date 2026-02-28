class Role < ApplicationRecord
  belongs_to :created_by, class_name: "AdminUser"
  has_many :admin_roles, dependent: :destroy
  has_many :admin_users, through: :admin_roles

  serialize :module_access, type: Array, coder: YAML

  validates :name, presence: true, uniqueness: true

  validate :validate_module_access

  ALLOWED_MODULES = %w[ accounts addresses admin_users roles brands categories cat_filters contact_us dealers dealer_locations dealer_profiles dealer_products products product_specifications product_variants reviews notifications orders analytics coupons settings ]

  def validate_module_access
    invalid = module_access - ALLOWED_MODULES
    errors.add(:module_access, "Invalid modules") if invalid.any?
  end
end
