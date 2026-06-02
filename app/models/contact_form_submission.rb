class ContactFormSubmission < ApplicationRecord
  belongs_to :admin_user, optional: true

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(status: %w(received)) }
  scope :responded, -> { where(status: 'responded') }

  after_create :send_confirmation_email

  private

  def send_confirmation_email
    ContactMailer.contact_form_received(self).deliver_later
  end
end
