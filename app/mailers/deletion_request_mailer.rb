class DeletionRequestMailer < ApplicationMailer

  def request_created(super_admin, request)
    @super_admin = super_admin
    @request = request

    mail(
      to: super_admin.email,
      subject: "Account Deletion Request"
    )
  end

  def approved(account, approved_by)
    @account = account
    @approved_by = approved_by

    mail(
      to: account.email,
      subject: "Account Deletion Approved"
    )
  end

  def rejected(account, reason)
    @account = account
    @reason = reason

    mail(
      to: account.email,
      subject: "Account Deletion Rejected"
    )
  end

  def direct_deleted(account, actor)
    @account = account
    @actor = actor

    mail(
      to: account.email,
      subject: "Account Deleted"
    )
  end

  def super_admin_direct_deleted(super_admin, account, actor)
    @super_admin = super_admin
    @account = account
    @actor = actor

    mail(
      to: super_admin.email,  
      subject: "Account Deleted"
    )
  end
end