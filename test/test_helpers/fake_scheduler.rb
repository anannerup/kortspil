# Records what the bord's actions schedule (Table::Surroundings#scheduler) instead of enqueuing jobs, so tests
# run bot turns, next runder, clock ticks and the end of bank windows by hand.
class FakeScheduler
  attr_reader :turns, :deals, :ticks, :bank_windows

  def initialize
    @turns = []
    @deals = []
    @ticks = []
    @bank_windows = []
  end

  def bot_turn(**turn) = @turns << turn
  def next_runde(**deal) = @deals << deal
  def tick(**tick) = @ticks << tick
  def close_bank_window(**window) = @bank_windows << window
end
