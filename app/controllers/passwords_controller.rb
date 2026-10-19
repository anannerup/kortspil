# Lets a signed-in user change their own password. There is no email reset.
class PasswordsController < ApplicationController
  nav_area :konto

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    @user.assign_attributes(password_params)

    if @user.save(context: :password_change)
      redirect_to root_path, notice: "Din adgangskode er ændret."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def password_params
      params.expect(user: [ :password_challenge, :password, :password_confirmation ])
    end
end
