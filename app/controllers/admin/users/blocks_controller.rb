class Admin::Users::BlocksController < Admin::Users::BaseController
  def create
    @user.block!
    redirect_with_notice "#{@user.username} er blokeret og logget ud."
  end

  # Unblocking lets the user back in as approved.
  def destroy
    @user.approved!
    redirect_with_notice "#{@user.username} er ikke længere blokeret."
  end
end
