class AdminUser < ApplicationRecord
  has_secure_password validations: false
  acts_as_paranoid
  attr_accessor :generated_password

  DOCUMENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/jpg
    application/pdf
  ].freeze
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
  has_one_attached :staff_profile_pic
  has_many_attached :marksheets

  enum :status, { active: 'active', inactive: 'inactive' }
  scope :approved, -> { where(approval_status: "approved") }
  scope :pending_approval, -> { where(approval_status: "pending") }

  # validates :email, uniqueness: { case_sensitive: false }, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP }
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
  validate :marksheets_validity

  before_create :generate_password
  before_validation :normalize_email
  before_validation :normalize_phone

  def super_admin?
    is_super_admin
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

  # def staff_profile_pic_presence_and_validity
  #   # unless staff_profile_pic.attached?
  #   #   errors.add(:staff_profile_pic, "is required")
  #   #   return
  #   # end

  #   blob = staff_profile_pic.blob
  #   # if blob.blank?
  #   #   errors.add(:staff_profile_pic, "contains an invalid file")
  #   #   return
  #   # end

  #   # unless blob.content_type.to_s.start_with?("image/")
  #   #   errors.add(:staff_profile_pic, "must be an image")
  #   # end

  #   errors.add(:staff_profile_pic, "must be 5 MB or smaller") if blob.byte_size > 5.megabytes
  # end

  def marksheets_validity
    return unless marksheets.attached?

    marksheets.each do |attachment|
      blob = attachment.blob

      if blob.blank?
        errors.add(:marksheets, "contains an invalid file")
        next
      end

      unless DOCUMENT_TYPES.include?(blob.content_type.to_s)
        errors.add(:marksheets, "must be JPG, PNG, WEBP, or PDF")
      end

      errors.add(:marksheets, "files must be 5 MB or smaller") if blob.byte_size > 5.megabytes
    end
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
end
