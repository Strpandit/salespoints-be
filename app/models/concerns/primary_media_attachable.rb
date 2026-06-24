module PrimaryMediaAttachable
  extend ActiveSupport::Concern

  included do
    attr_accessor :primary_new_media_index

    before_save :remember_media_attachment_count
    after_save :resolve_primary_new_media_index
  end

  def ordered_media_attachments
    attachments = media_attachments.to_a
    return attachments if primary_media_blob_id.blank?

    primary, rest = attachments.partition { |attachment| attachment.blob_id == primary_media_blob_id }
    primary + rest
  end

  private

  def remember_media_attachment_count
    @media_attachment_count_before_save = media.attached? ? media_attachments.count : 0
  end

  def resolve_primary_new_media_index
    index = primary_new_media_index
    self.primary_new_media_index = nil
    return if index.blank?

    idx = index.to_i
    attachments = media_attachments.order(:created_at).to_a
    target = attachments[@media_attachment_count_before_save.to_i + idx]
    return unless target

    update_column(:primary_media_blob_id, target.blob_id)
  end
end
