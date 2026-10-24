# "Glemt adgangskode?": there is no email in v1, so a user who forgot their
# password asks here and the admin sets a new one (Admin::Users::Passwords).
# The answer is the same whether or not the user exists, so the form cannot
# be used to find out who has an account.
class PasswordResetRequestsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { redirect_to new_password_reset_request_path, alert: "For mange forsøg. Prøv igen om lidt." }

  def new
  end

  def create
    User.find_by_login(params[:login])&.request_password_reset!
    redirect_to new_session_path, notice: "Tak. Hvis brugeren findes, får administratoren besked og sætter en ny adgangskode for dig."
  end
end
