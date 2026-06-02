class SupportMailer < ApplicationMailer
  default from: ENV['MAILER_FROM'] || 'support@salespoints.com'

  def ticket_created(ticket)
    @ticket = ticket
    @requester_name = ticket.requester_name
    @requester_email = ticket.requester_email

    mail(to: @requester_email, subject: "Support Ticket Created: #{ticket.ticket_number}")
  end

  def ticket_updated(ticket)
    @ticket = ticket
    @requester_name = ticket.requester_name
    @requester_email = ticket.requester_email

    mail(to: @requester_email, subject: "Support Ticket Updated: #{ticket.ticket_number}")
  end

  def ticket_message_added(ticket, message)
    @ticket = ticket
    @message = message
    @requester_email = ticket.requester_email

    mail(to: @requester_email, subject: "New Response on Ticket #{ticket.ticket_number}")
  end

  def ticket_assigned(ticket, admin)
    @ticket = ticket
    @admin = admin

    mail(to: admin.email, subject: "Ticket Assigned to You: #{ticket.ticket_number}")
  end

  def ticket_resolved(ticket)
    @ticket = ticket
    @requester_email = ticket.requester_email

    mail(to: @requester_email, subject: "Your Ticket Has Been Resolved: #{ticket.ticket_number}")
  end

  def ticket_closed(ticket)
    @ticket = ticket
    @requester_email = ticket.requester_email

    mail(to: @requester_email, subject: "Support Ticket Closed: #{ticket.ticket_number}")
  end
end
