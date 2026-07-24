class Address < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :dealer, optional: true

  enum :address_type, { home: 0, office: 1, others: 2 }

  validates :address_line1, :city, :state, :postal_code, presence: true
  validates :postal_code, format: { with: /\A[0-9]{6}\z/, message: "must be 6 digits" }

  before_validation :normalize_postal_code
  before_save :ensure_single_default
  after_save :sync_coordinates_from_address, if: :should_sync_coordinates?

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_dealer, ->(dealer_id) { where(dealer_id: dealer_id) }

  def full_address
    [address_line1, address_line2, city, state, postal_code, country].compact.join(", ")
  end

  def as_order_payload
    {
      "name" => name,
      "phone" => phone,
      "address_line1" => address_line1,
      "address_line2" => address_line2,
      "city" => city,
      "state" => state,
      "country" => country,
      "postal_code" => postal_code,
      "latitude" => latitude&.to_f,
      "longitude" => longitude&.to_f
    }
  end

  private

  def normalize_postal_code
    self.postal_code = postal_code.to_s.strip if postal_code.present?
  end

  def ensure_single_default
    return unless is_default_changed? && is_default
    
    if account_id.present?
      Address.where(account_id: account_id).where.not(id: id).update_all(is_default: false)
    elsif dealer_id.present?
      Address.where(dealer_id: dealer_id).where.not(id: id).update_all(is_default: false)
    end
  end
  
  def should_sync_coordinates?
    (account_id.present? || dealer_id.present?) && 
    (latitude.blank? || longitude.blank? || saved_change_to_address_line1? || saved_change_to_postal_code?)
  end

  def sync_coordinates_from_address
    return if full_address.blank?
    
    result = GoogleMapsService.instance.geocode(full_address)
    return if result.blank?
    
    update_columns(
      latitude: result[:latitude],
      longitude: result[:longitude],
      updated_at: Time.current
    )
  rescue StandardError
    # coordinates are optional; order flow can geocode pincode at runtime
  end
end
