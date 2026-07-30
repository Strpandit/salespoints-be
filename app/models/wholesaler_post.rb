class WholesalerPost < ApplicationRecord
  include AttachableMediaValidations

  belongs_to :dealer
  belongs_to :dealer_product, optional: true
  belongs_to :reviewed_by_admin, class_name: "AdminUser", optional: true
  has_many :wholesaler_post_ratings, dependent: :destroy
  has_many_attached :media

  APPROVE_STATUSES = %w[pending approved rejected].freeze

  validates :title, presence: true
  validates :approve_status, inclusion: { in: APPROVE_STATUSES }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
  validates :rating_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :media_files_valid
  validate :validate_pincodes_format

  scope :visible_to_marketplace, -> {
    where(approve_status: "approved")
      .where("(reuploaded_at >= ?) OR (reuploaded_at IS NULL AND created_at >= ?)", 7.days.ago, 7.days.ago)
  }
  scope :by_pincode, ->(pincode) { where("? = ANY(pincodes)", pincode) }
  scope :by_pincodes, ->(pincodes) { where("pincodes && ARRAY[?]::varchar[]", pincodes) }
  
  def effective_hsn_code
    return hsn_code if hsn_code.present?
    return dealer_product&.effective_hsn_code if dealer_product.present?
    nil
  end
  
  def visible_to_others?
    approve_status == "approved" && !is_expired?
  end

  def visible_until
    base_date = reuploaded_at.presence || created_at
    base_date&.+(7.days)
  end

  def can_reupload?
   approve_status == "approved" && is_expired?
  end

  def reupload!
    return false unless can_reupload?

    update!(
      approve_status: 'pending',
      reviewed_at: nil,
      rejection_reason: nil,
      reviewed_by_admin: nil,
      updated_at: Time.current,
      reuploaded_at: Time.current
    )
  end

  def is_expired?
    visible_until.present? && visible_until <= Time.current
  end

  private

  def media_files_valid
    validate_attachment_set(:media)
  end

  def validate_pincodes_format
    return if pincodes.blank?
    invalid = pincodes.reject { |p| p.to_s.match?(/\A[1-9][0-9]{5}\z/) }
    if invalid.present?
      errors.add(:pincodes, "contain invalid pincodes: #{invalid.join(', ')}")
    end
  end
end
