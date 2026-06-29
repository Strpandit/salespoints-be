class DealerProfile < ApplicationRecord
  include AttachableMediaValidations

  belongs_to :dealer
  has_many_attached :store_image
  has_many_attached :aadhar_card
  has_one_attached :pan_card
  has_one_attached :gst_certificate
  has_one_attached :cancel_cheque

  validates :business_name, :aadhar_number, presence: true
  validate :attachments_validity

  private

  def attachments_validity
    validate_attachment_set(:store_image, required: new_record?)
    validate_document_attachment_set(:aadhar_card)
    validate_document_attachment(:pan_card)
    validate_document_attachment(:gst_certificate)
    validate_document_attachment(:cancel_cheque)
  end
end
