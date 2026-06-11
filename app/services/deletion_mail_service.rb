class DeletionMailService
  class << self
    def request_created(request)
      AdminUser.where(is_super_admin: true).find_each do |admin|
        next if admin.email.blank?

        DeletionRequestMailer
          .request_created(admin, request)
          .deliver_later
      end
    end

    def approved(request, actor)
      account = request.requestable

      return if account.email.blank?

      DeletionRequestMailer
        .approved(account, actor)
        .deliver_later
    end

    def rejected(request, reason)
      account = request.requestable

      return if account.email.blank?

      DeletionRequestMailer
        .rejected(account, reason)
        .deliver_later
    end

    def direct_deleted(account, actor)
      return if account.email.blank?

      DeletionRequestMailer
        .direct_deleted(account, actor)
        .deliver_later

      AdminUser.where(is_super_admin: true).find_each do |admin|
        next if admin.email.blank?

        DeletionRequestMailer
          .super_admin_direct_deleted(
            admin,
            account,
            actor
          )
          .deliver_later
      end
    end
  end
end