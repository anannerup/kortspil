# Which area of the site a controller's pages belong to, read by the layout's
# top bar. "Spil" is the game world (lobby, tables); "Konto" the account
# world (friends, password, admin); "Regelbog" the rules page. The default
# is :spil.
#
#   class FriendshipsController < ApplicationController
#     nav_area :konto
#   end
#
#   class TablesController < ApplicationController
#     nav_style :compact   # thinner bar so the table gets the room
#   end
module Navigation
  extend ActiveSupport::Concern

  AREAS = %i[ spil regelbog konto ].freeze
  STYLES = %i[ full compact ].freeze

  included do
    class_attribute :navigation_area, instance_writer: false, default: :spil
    class_attribute :navigation_style, instance_writer: false, default: :full
    helper_method :navigation_area, :navigation_style, :show_navigation?
  end

  class_methods do
    # nil means no tab is active (e.g. the error pages).
    def nav_area(area)
      raise ArgumentError, "unknown nav area #{area.inspect}" unless area.nil? || AREAS.include?(area)

      self.navigation_area = area
    end

    def nav_style(style)
      raise ArgumentError, "unknown nav style #{style.inspect}" unless STYLES.include?(style)

      self.navigation_style = style
    end
  end

  private
    # Only signed-in, approved users get the bar. Pending and rejected users
    # see the waiting page with "Log ud" only; visitors see login and signup.
    def show_navigation?
      authenticated? && Current.user.approved?
    end
end
