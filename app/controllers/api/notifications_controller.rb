module Api
  class NotificationsController < ApplicationController
    def index
      notifications = paginated_notifications

      render json: {
        data: notifications[:records],
        meta: notifications[:meta]
      }, status: :ok
    end

    def unread_count
      render json: { unread_count: notifications_scope.unread.count }, status: :ok
    end

    def mark_read
      item = notifications_scope.find_by(id: params[:id])
      return render json: { error: "Notification not found" }, status: :not_found unless item

      item.mark_read!
      render json: { message: "Notification updated" }, status: :ok
    end

    def mark_all_read
      notifications_scope.unread.update_all(read_at: Time.current)
      render json: { message: "All notifications marked as read" }, status: :ok
    end

    private

    def notifications_scope
      if current_admin.present?
        current_admin.notifications.recent
      elsif current_dealer.present?
        current_dealer.notifications.recent
      elsif current_account.present?
        current_account.notifications.recent
      else
        Notification.none
      end
    end

    def paginated_notifications
      items = notifications_scope.map { |item| serialize_notification(item) }

      sorted = items.sort_by { |item| item[:created_at] || Time.at(0) }.reverse
      page = params[:page].presence.to_i
      per_page = params[:per_page].presence.to_i
      page = 1 if page <= 0
      per_page = 20 if per_page <= 0
      paginated = Kaminari.paginate_array(sorted).page(page).per(per_page)

      {
        records: paginated,
        meta: {
          current_page: paginated.current_page,
          next_page: paginated.next_page,
          prev_page: paginated.prev_page,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        }
      }
    end

    def serialize_notification(item)
      unread = item.read_at.blank?
      {
        id: item.id,
        notification_type: item.notification_type,
        kind: item.notification_type,
        title: item.title,
        body: item.body,
        message: item.body,
        payload: item.payload || {},
        notifiable_type: item.notifiable_type,
        notifiable_id: item.notifiable_id,
        receiver_type: item.receiver_type,
        receiver_id: item.receiver_id,
        read_at: item.read_at,
        sent_at: item.sent_at,
        status: unread ? "unread" : "read",
        created_at: item.created_at
      }
    end
  end
end
