class ReportAuditLog < ApplicationRecord
  belongs_to :user, polymorphic: true

  validates :user_type, :user_id, :report_key, :format, :downloaded_at, presence: true
end
