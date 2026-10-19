class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :redirect_signed_in_user

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      redirect_to root_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.expect(user: [ :username, :email_address, :password, :password_confirmation ])
    end

    def redirect_signed_in_user
      redirect_to root_path if authenticated?
    end
end
