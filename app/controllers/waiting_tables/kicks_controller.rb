# The vært kicks a player before the start (TableCommands#kick).
class WaitingTables::KicksController < ApplicationController
  include WaitingTableActions

  def create
    answer TableCommands.new.kick(table: @table, user: Current.user, seat:)
  end
end
