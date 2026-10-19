class Admin::Users::ApprovalsController < Admin::Users::BaseController
  def create
    @user.approved!
    redirect_with_notice "#{@user.username} er godkendt."
  end

  # Unapprove: back to awaiting approval.
  def destroy
    @user.pending!
    redirect_with_notice "#{@user.username} afventer nu godkendelse igen."
  end
end
