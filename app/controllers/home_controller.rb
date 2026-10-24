# The lobby. The React lobby starts from the open tables listed here and
# then follows LobbyChannel. A player whose spil is waiting for them
# (frakoblet from it) sees a banner with the time left to come back.
class HomeController < ApplicationController
  def show
    @lobby_tables = LobbyChannel.tables_message["tables"]
    @current_table = Current.user.current_table
    @seconds_to_return = @current_table&.seconds_to_return(Current.user, now: Time.current)
  end
end
