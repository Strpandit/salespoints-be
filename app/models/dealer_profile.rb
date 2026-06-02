class DealerProfile < ApplicationRecord
  include AttachableMediaValidations

  belongs_to :dealer
  has_many_attached :store_image

  validates :business_name, :aadhar_number, presence: true
  validate :store_image_presence_and_validity

  private

  def store_image_presence_and_validity
    validate_attachment_set(:store_image, required: true)
  end
end
