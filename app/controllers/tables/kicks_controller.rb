# The vært kicks a player before the start (TableCommands#kick).
class Tables::KicksController < ApplicationController
  include TableRefusals

  def create
    table = Table.find(params[:table_id])
    answer TableCommands.new.kick(table:, user: Current.user, seat: Integer(params[:position].to_s, exception: false))
  end
end
