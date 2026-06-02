module AttachableMediaValidations
  extend ActiveSupport::Concern

  IMAGE_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/jpg
    image/gif
  ].freeze

  VIDEO_TYPES = %w[
    video/mp4
    video/quicktime
    video/webm
    video/ogg
    video/x-msvideo
    video/mpeg
  ].freeze

  MAX_IMAGE_SIZE = 5.megabytes
  MAX_VIDEO_SIZE = 50.megabytes

  private

  def validate_attachment_set(name, required: false)
    attachments = public_send(name)

    unless attachments.attached?
      errors.add(name, "is required") if required
      return
    end

    blobs =
      if attachments.respond_to?(:attachments)
        attachments.attachments
      else
        [attachments]
      end

    blobs.each do |attachment|
      validate_attachment_blob(name, attachment)
    end
  end

  def validate_attachment_blob(name, attachment)
    blob = attachment.blob

    unless blob
      errors.add(name, "contains an invalid file")
      return
    end

    content_type = blob.content_type.to_s

    if IMAGE_TYPES.include?(content_type)
      validate_image_size(name, blob)
    elsif VIDEO_TYPES.include?(content_type)
      validate_video_size(name, blob)
    else
      errors.add(name, "supports images and videos only")
    end
  end

  def validate_image_size(name, blob)
    return unless blob.byte_size > MAX_IMAGE_SIZE

    errors.add(name, "images must be 5 MB or smaller")
  end

  def validate_video_size(name, blob)
    return unless blob.byte_size > MAX_VIDEO_SIZE

    errors.add(name, "videos must be 50 MB or smaller")
  end
end