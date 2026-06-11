class DeletionNotificationService
  class << self
    def request_created(request)
      AdminUser.where(is_super_admin: true).find_each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: request.requestable,
          notifiable: request,
          kind: "deletion_request_created",
          title: "Deletion Request",
          message: "#{request.requestable.full_name} requested account deletion"
        )
      end
    end

    def approved(request, actor)
      account = request.requestable

      NotificationService.deliver(
        recipient: account,
        actor: actor,
        notifiable: request,
        kind: "deletion_request_approved",
        title: "Deletion Approved",
        message: "Your account deletion request has been approved."
      )

      NotificationService.deliver(
        recipient: actor,
        actor: actor,
        notifiable: request,
        kind: "deletion_request_approved",
        title: "Account Deleted",
        message: "#{account.full_name} account deleted successfully."
      )
    end

    def rejected(request, actor, reason)
      NotificationService.deliver(
        recipient: request.requestable,
        actor: actor,
        notifiable: request,
        kind: "deletion_request_rejected",
        title: "Deletion Request Rejected",
        message: reason
      )
    end

    def direct_deleted(account, actor)
      AdminUser.where(is_super_admin: true).find_each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: actor,
          notifiable: account,
          kind: "account_deleted",
          title: "Account Deleted",
          message: "#{account.full_name} account deleted by #{actor.full_name}"
        )
      end
    end
  end
end