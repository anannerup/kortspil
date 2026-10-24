# The lobby. The React lobby starts from the open tables listed here and
# then follows LobbyChannel.
class HomeController < ApplicationController
  def show
    @lobby_tables = LobbyChannel.tables_message["tables"]
    @current_table = Current.user.current_table
  end
end
