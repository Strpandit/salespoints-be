class ContactMailer < ApplicationMailer
  default from: ENV['MAILER_FROM'] || 'contact@salespoints.com'

  def contact_form_received(submission)
    @submission = submission

    mail(to: submission.email, subject: 'We received your message - Salespoints')
  end

  def new_contact_form(submission, admin)
    @submission = submission
    @admin = admin

    mail(to: admin.email, subject: "New Contact Form Submission: #{submission.subject}")
  end

  def contact_form_response(submission)
    @submission = submission

    mail(to: submission.email, subject: "Response to Your Message: #{submission.subject}")
  end
end
