# Everything under /admin. Non-admins get a 404 so the admin area doesn't
# reveal that it exists; logged-out visitors are sent to login as usual.
class Admin::BaseController < ApplicationController
  before_action :require_admin

  private
    def require_admin
      head :not_found unless Current.user.admin?
    end
end
