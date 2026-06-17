class AdminUser < ApplicationRecord
  has_secure_password validations: false
  acts_as_paranoid
  attr_accessor :generated_password
  include AttachableMediaValidations

  APPROVAL_STATUSES = %w[pending approved rejected].freeze

  has_many :admin_roles, dependent: :destroy
  has_many :roles, through: :admin_roles
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :deletion_requests, as: :requestable, dependent: :destroy
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy
  has_many :support_tickets, foreign_key: 'admin_user_id', dependent: :destroy
  has_many :assigned_tickets, class_name: 'SupportTicket', foreign_key: 'assigned_to_id', dependent: :nullify
  has_many :ticket_messages, foreign_key: 'admin_user_id', dependent: :destroy
  has_many :contact_form_submissions, dependent: :destroy
  belongs_to :approved_by, class_name: "AdminUser", optional: true
  belongs_to :deleted_by, class_name: "AdminUser", optional: true
  has_many :deleted_admins, class_name: "AdminUser", foreign_key: :deleted_by_id

  has_many_attached :marksheets
  has_one_attached :staff_profile_pic
  has_one_attached :aadhar_card
  has_one_attached :pan_card

  enum :status, { active: 'active', inactive: 'inactive' }
  scope :approved, -> { where(approval_status: "approved") }
  scope :pending_approval, -> { where(approval_status: "pending") }

  validates :email,
    allow_blank: true,
    uniqueness: { case_sensitive: false },
    format: {
      with: /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@
            [a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}\z/x
    }
  validates :phone, uniqueness: true, allow_blank: true
  validates :alternate_phone, allow_blank: true, uniqueness: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  # validates :address, :aadhar_number, :pan_number, :bank_name, :bank_account_number,
  #           :ifsc_code, :account_holder_name, :tenth_school_name, :tenth_board,
  #           :tenth_passing_year, :tenth_percentage, :twelfth_school_name, :twelfth_board,
  #           :twelfth_passing_year, :twelfth_percentage, presence: true
  # validate :staff_profile_pic_presence_and_validity
  validate :attachments_validity
  validate :validate_pincodes_format

  before_create :generate_password
  before_validation :normalize_email
  before_validation :normalize_phone

  def super_admin?
    is_super_admin || roles.active.exists?(name: "super_admin")
  end

  def accessible_pincodes
    return nil if super_admin?
    pincodes.presence || []
  end

  def can_access_pincode?(pincode)
    return true if super_admin?
    return false if pincodes.blank?
    pincodes.include?(pincode)
  end

  def accessible_dealers(dealers_scope = Dealer.all)
    return dealers_scope if super_admin?
    return dealers_scope.none if pincodes.blank?
    dealers_scope.where(pincode: pincodes)
  end

  def accessible_wholesale_posts(posts_scope = WholesalerPost.all)
    return posts_scope if super_admin?
    return posts_scope.none if pincodes.blank?
    posts_scope.where("pincodes && ARRAY[?]::varchar[]", pincodes)
  end

  def approver_admin?
    return true if super_admin?

    roles.active.any? { |role| role.name.to_s.strip.downcase.in?(["sub admin", "sub_admin"]) }
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

  def joining_form_completed?
    required_values = [
      address, aadhar_number, pan_number, bank_name, bank_account_number, ifsc_code,
      account_holder_name, tenth_school_name, tenth_board, tenth_passing_year,
      tenth_percentage, twelfth_school_name, twelfth_board, twelfth_passing_year,
      twelfth_percentage
    ]

    required_values.all?(&:present?) && staff_profile_pic.attached?
  end

  def approved?
    approval_status == "approved"
  end

  def otp_valid?(otp)
    otp_pin.to_s == otp.to_s && otp_sent_at.present? && otp_sent_at > 5.minutes.ago
  end

  def clear_otp!
    update!(otp_pin: nil, otp_sent_at: nil)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def normalize_phone
    mobile = phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    self.phone = mobile.presence
    alternate_mobile = alternate_phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    self.alternate_phone = alternate_mobile.presence
    if country_code.present?
      self.country_code = "+#{country_code.gsub(/\D/, '')}"
    end
  end

  def attachments_validity
    validate_document_attachment_set(:marksheets)
    validate_document_attachment(:staff_profile_pic)
    validate_document_attachment(:aadhar_card)
    validate_document_attachment(:pan_card)
  end

  def generate_password
    return if password.present?

    year = Time.current.year.to_s
    email_part = email.split('@').first.to_s[0, 3]
    email_part = email_part.ljust(3, "x")
    random_digits = SecureRandom.random_number(10_000).to_s.rjust(4, "0")
    generated_password = "#{email_part}#{random_digits}"
    self.generated_password = generated_password
    self.password = generated_password
    self.password_confirmation = generated_password
  end

  def validate_pincodes_format
    return if pincodes.blank?
    invalid = pincodes.reject { |p| p.to_s.match?(/\A[1-9][0-9]{5}\z/) }
    if invalid.present?
      errors.add(:pincodes, "contain invalid pincodes: #{invalid.join(', ')}")
    end
  end
end
