class AdminRole < ApplicationRecord
  belongs_to :admin_user
  belongs_to :role

  validates :role_id, uniqueness: { scope: :admin_user_id }
end
