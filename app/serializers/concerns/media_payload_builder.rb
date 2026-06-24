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
    file.respond_to?(:blob_id) ? file.blob_id : file.id
  end

  def file_payload(file)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: file.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(file, host: host),
      filename: file.filename.to_s,
      content_type: file.content_type.to_s
    }
  end
end
