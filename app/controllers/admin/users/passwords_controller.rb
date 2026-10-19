# The admin types a new password for a user who forgot theirs (no email reset in v1).
class Admin::Users::PasswordsController < Admin::Users::BaseController
  def edit
  end

  def update
    if @user.reset_password(**password_params.to_h.symbolize_keys)
      redirect_to admin_users_path, notice: "Ny adgangskode er sat for #{@user.username}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def password_params
      params.expect(user: [ :password, :password_confirmation ])
    end
end
