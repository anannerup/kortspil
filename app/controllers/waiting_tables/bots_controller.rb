# The vært puts a bot in an empty seat, or takes one out, before the start.
class WaitingTables::BotsController < ApplicationController
  include WaitingTableActions

  def create
    answer TableCommands.new.add_bot(table: @table, user: Current.user, seat:)
  end

  def destroy
    answer TableCommands.new.remove_bot(table: @table, user: Current.user, seat:)
  end
end
