class AdminUserSerializer < ApplicationSerializer
  attributes :first_name, :last_name, :email, :phone, :alternate_phone, :address, :salary,
             :aadhar_number, :pan_number, :bank_name, :bank_account_number,
             :ifsc_code, :account_holder_name, :tenth_school_name, :tenth_board,
             :tenth_passing_year, :tenth_percentage, :twelfth_school_name,
             :twelfth_board, :twelfth_passing_year, :twelfth_percentage, :status,
             :country_code, :is_super_admin, :full_name, :pending_deletion_request, :joining_date,
             :role, :staff_profile_pic, :aadhar_card, :pan_card, :marksheets, :joining_form_completed,
             :approval_status, :approved_at, :approved_by_name, :otp_verified, :deleted_at, :deleted_by

  def pending_deletion_request
    object.deletion_requests.pending.exists?
  end

  def joining_form_completed
    object.joining_form_completed?
  end

  def otp_verified
    object.otp_pin.blank?
  end

  def role
    object.roles&.map do |role|
      {
        id: role.id,
        name: role.name,
        is_active: role.is_active,
        module_access: role.module_access,
        module_permissions: role.module_permissions
      }
    end
  end

  def staff_profile_pic
    return nil unless object.staff_profile_pic.attached?

    file_payload(object.staff_profile_pic)
  end

  def aadhar_card
    return nil unless object.aadhar_card.attached?

    file_payload(object.aadhar_card)
  end

  def pan_card
    return nil unless object.pan_card.attached?

    file_payload(object.pan_card)
  end

  def approved_by_name
    object.approved_by&.full_name
  end

  def marksheets
    object.marksheets.map { |file| file_payload(file) }
  end

  private

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
