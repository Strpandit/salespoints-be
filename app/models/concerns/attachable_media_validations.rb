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

  DOCUMENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/jpg
    application/pdf
  ].freeze

  MAX_DOCUMENT_SIZE = 15.megabytes
  MAX_IMAGE_SIZE = 10.megabytes
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
    content_type = inferred_content_type(blob) if content_type.blank? || content_type == "application/octet-stream"

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

    errors.add(name, "images must be 10 MB or smaller")
  end

  def validate_video_size(name, blob)
    return unless blob.byte_size > MAX_VIDEO_SIZE

    errors.add(name, "videos must be 50 MB or smaller")
  end

  def inferred_content_type(blob)
    extension = blob.filename.extension.to_s.downcase
    case extension
    when "jpg", "jpeg" then "image/jpeg"
    when "png" then "image/png"
    when "webp" then "image/webp"
    when "gif" then "image/gif"
    when "mp4" then "video/mp4"
    when "webm" then "video/webm"
    when "mov" then "video/quicktime"
    else
      blob.content_type.to_s
    end
  end

  def validate_document_attachment(name, required: false)
    attachment = public_send(name)

    unless attachment.attached?
      errors.add(name, "is required") if required
      return
    end

    blob = attachment.blob

    unless blob
      errors.add(name, "contains an invalid file")
      return
    end

    unless DOCUMENT_TYPES.include?(blob.content_type.to_s)
      errors.add(name, "must be PDF file")
      return
    end

    if blob.byte_size > MAX_DOCUMENT_SIZE
      errors.add(name, "must be 15 MB or smaller")
    end
  end

  def validate_document_attachment_set(name, required: false)
    attachments = public_send(name)

    unless attachments.attached?
      errors.add(name, "is required") if required
      return
    end

    attachments.each do |attachment|
      blob = attachment.blob

      unless blob
        errors.add(name, "contains an invalid file")
        next
      end

      unless DOCUMENT_TYPES.include?(blob.content_type.to_s)
        errors.add(name, "must be PDF file")
        next
      end

      if blob.byte_size > MAX_DOCUMENT_SIZE
        errors.add(name, "must be 15 MB or smaller")
      end
    end
  end
end