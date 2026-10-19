class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  allow_unapproved_access only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "For mange forsøg. Prøv igen om lidt." }

  def new
  end

  def create
    user = User.authenticate_by_login(params[:login], params[:password])

    if user.nil?
      redirect_to new_session_path, alert: "Forkert brugernavn, e-mail eller adgangskode."
    elsif user.blocked?
      redirect_to new_session_path, alert: BLOCKED_MESSAGE
    else
      start_new_session_for user
      redirect_to after_authentication_url
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
