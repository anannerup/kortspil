# The vært puts a bot in an empty seat (at the level they chose: Let,
# Mellem or Svær, Mellem unless they chose), changes its level, or takes it
# out, before the start.
class WaitingTables::BotsController < WaitingTables::BaseController
  def create
    render_outcome @table.add_bot(user: Current.user, seat:, level: params.fetch(:level, Table::Seating::BOT_LEVEL))
  end

  def update
    render_outcome @table.change_bot_level(user: Current.user, seat:, level: params[:level])
  end

  def destroy
    render_outcome @table.remove_bot(user: Current.user, seat:)
  end
end
