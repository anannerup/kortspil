# The regelbog: the rules of hjerterfri and es-makker as played here, and how
# the bots play them, in plain Danish. The content lives in the views
# (app/views/regelbog), the house rules' values come from the games' rules
# (GameRules.standard), so the page shows what the bords play by. It is
# public: visitors read it without the top bar and with a way to log in.
class RegelbogController < ApplicationController
  allow_unauthenticated_access only: :show
  nav_area :regelbog

  def show
    @hjerterfri = GameRules.standard("hjerterfri")
    @esmakker = GameRules.standard("esmakker")
    @runder = TableRules::STANDARD_RUNDER
  end
end
