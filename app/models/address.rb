class Address < ApplicationRecord
  belongs_to :account

  enum :address_type, { home: 0, office: 1, others: 2 }

  validates :address_line1, :city, :state, :postal_code, presence: true
  validates :postal_code, format: { with: /\A[0-9]{6}\z/, message: "must be 6 digits" }
  before_save :ensure_single_default

  def full_address
    [address_line1, address_line2, city, state, postal_code, country].compact.join(", ")
  end

  private

  def ensure_single_default
    if is_default_changed? && is_default
      Address.where(account_id: account_id).where.not(id: id).update_all(is_default: false)
    end
  end
end
