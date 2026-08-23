module MediaPayloadBuilder
  extend ActiveSupport::Concern

  private

  def build_media_payloads(files, primary_blob_id: nil)
    ordered = order_files_for_primary(files, primary_blob_id)
    ordered.map { |file| file_payload_with_primary(file, primary_blob_id) }
  end

  def order_files_for_primary(files, primary_blob_id)
    list = Array(files)
    return list if primary_blob_id.blank?

    primary, rest = list.partition { |file| blob_id_for(file) == primary_blob_id }
    primary + rest
  end

  def file_payload_with_primary(file, primary_blob_id)
    payload = file_payload(file)
    payload[:is_primary] = primary_blob_id.present? && blob_id_for(file) == primary_blob_id
    payload
  end

  def blob_id_for(file)
    return file.blob_id if file.respond_to?(:blob_id)
    return file.blob.id if file.respond_to?(:blob) && file.blob.present?
    file.id
  end

  def file_payload(file)
    return nil if file.blank?
    blob = file.respond_to?(:blob) && file.blob.present? ? file.blob : file
    return nil unless blob.respond_to?(:filename)

    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: blob.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(blob, host: host),
      filename: blob.filename.to_s,
      content_type: blob.content_type.to_s
    }
  rescue => e
    nil
  end
end
