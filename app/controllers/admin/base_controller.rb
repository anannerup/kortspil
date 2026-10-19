# Everything under /admin. Non-admins get a 404 so the admin area doesn't
# reveal that it exists; logged-out visitors are sent to login as usual.
class Admin::BaseController < ApplicationController
  nav_area :konto
  before_action :require_admin

  private
    # Same 404 page as any unknown URL (with the top bar), not a blank page.
    def require_admin
      raise ActionController::RoutingError, "Not Found" unless Current.user.admin?
    end
end
