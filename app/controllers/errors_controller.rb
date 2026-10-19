# Error pages, served through config.exceptions_app = routes. Approved users
# get the top bar as on every other page; everyone else gets "Til forsiden",
# so even an error has a way out.
class ErrorsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  nav_area nil

  MESSAGES = {
    400 => [ "Forkert forespørgsel", "Siden kunne ikke forstå forespørgslen." ],
    404 => [ "Siden findes ikke", "Siden, du leder efter, findes ikke, eller du har ikke adgang til den." ],
    406 => [ "Kan ikke vises", "Siden kan ikke vises i det format, du bad om." ],
    422 => [ "Ændringen blev afvist", "Prøv at genindlæse siden og gøre det igen." ],
    500 => [ "Der skete en fejl", "Noget gik galt hos os. Prøv igen om lidt." ]
  }.freeze

  def show
    @status = MESSAGES.key?(params[:code].to_i) ? params[:code].to_i : 500
    @title, @message = MESSAGES.fetch(@status)
    render :show, status: @status, formats: :html
  end

  private
    # A 500 may come from a broken database; never let the bar break the error page.
    def show_navigation?
      super
    rescue StandardError
      false
    end
end
