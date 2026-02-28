class DealerProfile < ApplicationRecord
  belongs_to :dealer

  validates :business_name, :aadhar_number, presence: true
end
