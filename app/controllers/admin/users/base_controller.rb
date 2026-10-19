# Actions the admin takes on one user. The admin can't use them on
# themselves, so they can't lock themselves out by mistake.
class Admin::Users::BaseController < Admin::BaseController
  before_action :set_user, :prevent_self_change

  private
    def set_user
      @user = User.find(params[:user_id])
    end

    def prevent_self_change
      redirect_back_or_to admin_users_path, alert: "Du kan ikke ændre din egen konto her." if @user == Current.user
    end

    def redirect_with_notice(notice)
      redirect_back_or_to admin_users_path, notice:
    end
end
