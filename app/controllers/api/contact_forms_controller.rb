class Api::ContactFormsController < ApplicationController
  # Submit contact form
  def create
    submission = ContactFormSubmission.new(contact_form_params)

    if submission.save
      # Notification is sent automatically via after_create callback
      # Send email to admins
      notify_admins_contact_form(submission)

      render json: {
        success: true,
        message: 'Thank you for contacting us. We will get back to you soon.',
        data: { id: submission.id }
      }, status: :created
    else
      render json: {
        success: false,
        errors: submission.errors
      }, status: :unprocessable_entity
    end
  end

  # Get submissions (admin only)
  def index
    authorize_admin!

    submissions = ContactFormSubmission.recent
    submissions = submissions.where(status: params[:status]) if params[:status].present?

    # Pagination
    page = params[:page] || 1
    per_page = params[:per_page] || 10
    submissions_paginated = submissions.paginate(page: page, per_page: per_page)

    render json: {
      success: true,
      data: submissions_paginated.as_json(include: :admin_user),
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: submissions.count
      }
    }
  end

  # Get single submission
  def show
    authorize_admin!

    submission = ContactFormSubmission.find(params[:id])
    submission.update(status: 'read') if submission.received?

    render json: {
      success: true,
      data: submission.as_json(include: :admin_user)
    }
  end

  # Respond to contact form
  def respond
    authorize_admin!

    submission = ContactFormSubmission.find(params[:id])
    admin = authenticate_admin

    if submission.update(
      admin_response: params[:response],
      admin_user: admin,
      status: 'responded',
      responded_at: Time.current
    )
      # Send response email to submitter
      ContactMailer.contact_form_response(submission).deliver_later

      render json: {
        success: true,
        message: 'Response sent successfully'
      }
    else
      render json: {
        success: false,
        errors: submission.errors
      }, status: :unprocessable_entity
    end
  end

  private

  def contact_form_params
    params.require(:contact_form).permit(:name, :email, :phone, :subject, :message)
  end

  def authenticate_admin
    token = request.headers['Authorization']&.split(' ')&.last
    return nil unless token

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      AdminUser.find(decoded['user_id'])
    rescue JWT::DecodeError
      nil
    end
  end

  def authorize_admin!
    admin = authenticate_admin
    render json: { success: false, error: 'Admin access required' }, status: :forbidden if admin.blank?
  end

  def notify_admins_contact_form(submission)
    AdminUser.where(is_super_admin: true).each do |admin|
      Notification.create!(
        receiver: admin,
        notifiable: submission,
        notification_type: 'contact_form',
        title: 'New Contact Form Submission',
        message: "New message from #{submission.name}: #{submission.subject}",
        is_read: false
      )

      # Send email
      ContactMailer.new_contact_form(submission, admin).deliver_later
    end
  end
end
