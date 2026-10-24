# The vært puts a bot in an empty seat, or takes one out, before the start.
class Tables::BotsController < ApplicationController
  include TableRefusals

  before_action :set_table

  def create
    answer TableCommands.new.add_bot(table: @table, user: Current.user, seat:)
  end

  def destroy
    answer TableCommands.new.remove_bot(table: @table, user: Current.user, seat:)
  end

  private

  def set_table
    @table = Table.find(params[:table_id])
  end

  def seat = Integer(params[:position].to_s, exception: false)

  def answer(outcome)
    return refused(outcome) if outcome.refused?

    redirect_to table_path(@table)
  end
end
