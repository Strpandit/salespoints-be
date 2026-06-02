module Api
  class SupportTicketsController < ApplicationController
    before_action :set_ticket, only: [:show, :update, :add_message, :assign, :resolve, :close]
    before_action :authorize_ticket_access!, only: [:show, :update, :add_message]
    before_action :authorize_admin_access!, only: [:assign, :resolve, :close, :statistics]

    def create
      ticket = SupportTicket.new(ticket_params)

      case current_user_type
      when "Account"
        ticket.account = current_account
        ticket.user_type = "account"
      when "Dealer"
        ticket.dealer = current_dealer
        ticket.user_type = "dealer"
      when "AdminUser"
        ticket.admin_user = current_admin
        ticket.user_type = "admin"
      else
        return render json: { success: false, error: "Unauthorized" }, status: :unauthorized
      end

      if ticket.save
        SupportMailer.ticket_created(ticket).deliver_later
        notify_admin_new_ticket(ticket)
        render json: { success: true, data: ticket_payload(ticket) }, status: :created
      else
        render json: { success: false, errors: ticket.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def index
      tickets = case current_user_type
                when "Account"
                  SupportTicket.for_user(current_account.id).recent
                when "Dealer"
                  SupportTicket.for_dealer(current_dealer.id).recent
                when "AdminUser"
                  current_admin.is_super_admin ? SupportTicket.recent : SupportTicket.where(assigned_to_id: current_admin.id).or(SupportTicket.for_admin(current_admin.id)).recent
                else
                  SupportTicket.none
                end

      tickets = tickets.by_status(params[:status]) if params[:status].present?
      tickets = tickets.by_priority(params[:priority]) if params[:priority].present?
      tickets = tickets.by_category(params[:category]) if params[:category].present?

      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 10).to_i
      paginated = tickets.page(page).per(per_page)

      render json: {
        success: true,
        data: paginated.map { |ticket| ticket_payload(ticket) },
        pagination: {
          current_page: paginated.current_page,
          per_page: per_page,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        }
      }
    end

    def show
      render json: { success: true, data: ticket_payload(@ticket, include_messages: true) }
    end

    def update
      if @ticket.update(update_ticket_params)
        SupportMailer.ticket_updated(@ticket).deliver_later
        create_ticket_notification(@ticket, "Ticket updated")
        render json: { success: true, data: ticket_payload(@ticket, include_messages: true) }
      else
        render json: { success: false, errors: @ticket.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def add_message
      sender_type = case current_user_type
                    when "Account" then "customer"
                    when "Dealer" then "dealer"
                    when "AdminUser" then "admin"
                    else "system"
                    end

      sender = case current_user_type
              when "Account" then current_account
              when "Dealer" then current_dealer
              when "AdminUser" then current_admin
              end

      message = @ticket.add_message(sender_type, params[:message], sender)

      if message.persisted?
        SupportMailer.ticket_message_added(@ticket, message).deliver_later
        create_ticket_notification(@ticket, "New message from #{message.sender_name}")
        @ticket.update(status: "in_progress") if sender_type == "admin" && @ticket.status == "open"
        @ticket.update(status: "waiting_customer") if sender_type == "admin"
        render json: { success: true, data: message_payload(message) }
      else
        render json: { success: false, errors: message.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def assign
      admin = AdminUser.find(params[:admin_id])
      @ticket.assign_to_admin(admin)
      SupportMailer.ticket_assigned(@ticket, admin).deliver_later
      render json: { success: true, data: ticket_payload(@ticket, include_messages: true) }
    end

    def resolve
      @ticket.resolve(params[:resolution_summary])
      SupportMailer.ticket_resolved(@ticket).deliver_later
      create_ticket_notification(@ticket, "Your ticket has been resolved")
      render json: { success: true, data: ticket_payload(@ticket, include_messages: true) }
    end

    def close
      @ticket.mark_as_closed
      SupportMailer.ticket_closed(@ticket).deliver_later
      render json: { success: true, data: ticket_payload(@ticket, include_messages: true) }
    end

    def statistics
      stats = {
        total: SupportTicket.count,
        open: SupportTicket.open.count,
        resolved: SupportTicket.resolved.count,
        closed: SupportTicket.closed.count,
        in_progress: SupportTicket.where(status: "in_progress").count,
        waiting_customer: SupportTicket.where(status: "waiting_customer").count,
        by_priority: SupportTicket.group(:priority).count,
        by_category: SupportTicket.group(:category).count,
        avg_resolution_time_hours: calculate_avg_resolution_time
      }

      render json: { success: true, data: stats }
    end

    private

    def set_ticket
      @ticket = SupportTicket.find_by(ticket_number: params[:id]) || SupportTicket.find_by(id: params[:id])
      return if @ticket.present?

      render json: { success: false, error: "Ticket not found" }, status: :not_found
    end

    def authorize_ticket_access!
      allowed = case current_user_type
                when "Account"
                  @ticket.account_id == current_account&.id
                when "Dealer"
                  @ticket.dealer_id == current_dealer&.id
                when "AdminUser"
                  current_admin&.is_super_admin || @ticket.assigned_to_id == current_admin&.id || @ticket.admin_user_id == current_admin&.id
                else
                  false
                end

      return if allowed

      render json: { success: false, error: "Access denied" }, status: :forbidden
    end

    def authorize_admin_access!
      return if current_user_type == "AdminUser"

      render json: { success: false, error: "Admin access required" }, status: :forbidden
    end

    def ticket_params
      params.require(:ticket).permit(:subject, :description, :category, :priority)
    end

    def update_ticket_params
      params.require(:ticket).permit(:priority, :status)
    end

    def notify_admin_new_ticket(ticket)
      AdminUser.where(is_super_admin: true).find_each do |admin|
        Notification.create!(
          receiver: admin,
          notifiable: ticket,
          notification_type: "new_ticket",
          title: "New Support Ticket: #{ticket.ticket_number}",
          body: "#{ticket.requester_name} created a new ticket: #{ticket.subject}",
          payload: { support_ticket_id: ticket.id }
        )
      end
    end

    def create_ticket_notification(ticket, message)
      recipient = case ticket.user_type
                  when "customer" then ticket.account
                  when "dealer" then ticket.dealer
                  when "admin" then ticket.admin_user
                  end
      return unless recipient

      Notification.create!(
        receiver: recipient,
        notifiable: ticket,
        notification_type: "ticket_update",
        title: "Ticket #{ticket.ticket_number} Updated",
        body: message,
        payload: { support_ticket_id: ticket.id }
      )
    end

    def ticket_payload(ticket, include_messages: false)
      payload = {
        id: ticket.id,
        ticket_number: ticket.ticket_number,
        subject: ticket.subject,
        description: ticket.description,
        category: ticket.category,
        priority: ticket.priority,
        status: ticket.status,
        user_type: ticket.user_type,
        requester_name: ticket.requester_name,
        requester_email: ticket.requester_email,
        created_at: ticket.created_at,
        updated_at: ticket.updated_at,
        resolved_at: ticket.resolved_at,
        resolution_summary: ticket.resolution_summary,
        messages_count: ticket.messages_count,
        assigned_to: ticket.assigned_to && {
          id: ticket.assigned_to.id,
          name: ticket.assigned_to.full_name,
          email: ticket.assigned_to.email
        },
        dealer: ticket.dealer && {
          id: ticket.dealer.id,
          dealer_code: ticket.dealer.dealer_code,
          full_name: ticket.dealer.full_name,
          email: ticket.dealer.email,
          business_name: ticket.dealer.dealer_profile&.business_name
        },
        account: ticket.account && {
          id: ticket.account.id,
          full_name: ticket.account.full_name,
          email: ticket.account.email
        },
        admin_user: ticket.admin_user && {
          id: ticket.admin_user.id,
          full_name: ticket.admin_user.full_name,
          email: ticket.admin_user.email
        }
      }

      payload[:messages] = ticket.messages.recent.map { |message| message_payload(message) } if include_messages
      payload
    end

    def message_payload(message)
      {
        id: message.id,
        sender_type: message.sender_type,
        sender_name: message.sender_name,
        message: message.message,
        is_internal: message.is_internal,
        created_at: message.created_at
      }
    end

    def calculate_avg_resolution_time
      resolved_tickets = SupportTicket.resolved.where.not(resolved_at: nil)
      return 0 if resolved_tickets.empty?

      total_seconds = resolved_tickets.sum { |ticket| (ticket.resolved_at - ticket.created_at).to_i }
      (total_seconds / resolved_tickets.count / 3600.0).round(2)
    end
  end
end
