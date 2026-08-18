module Api
  class DealerNotificationsController < ApplicationController
    def index
      scope = current_dealer.notifications.recent.select(&:visible_in_app?)
      items = Kaminari.paginate_array(scope).page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: items.map { |n| serialize_notification(n) },
        meta: {
          current_page: items.current_page,
          next_page: items.next_page,
          prev_page: items.prev_page,
          total_pages: items.total_pages,
          total_count: items.total_count
        },
        message: "Notifications fetched successfully"
      }, status: :ok
    end

    def mark_read
      item = current_dealer.notifications.find_by(id: params[:id])
      return render json: { error: "Notification not found" }, status: :not_found unless item

      item.mark_read!
      render json: { message: "Notification updated" }, status: :ok
    end

    def mark_all_read
      current_dealer.notifications.where(read_at: nil).find_each(&:mark_read!)
      render json: { message: "All notifications marked as read" }, status: :ok
    end

    private

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
        read_at: item.read_at,
        sent_at: item.sent_at,
        status: unread ? "unread" : "read",
        created_at: item.created_at
      }
    end
  end
end
