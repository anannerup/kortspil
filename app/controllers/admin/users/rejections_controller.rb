class Admin::Users::RejectionsController < Admin::Users::BaseController
  def create
    @user.rejected!
    redirect_with_notice "#{@user.username} er afvist."
  end
end
