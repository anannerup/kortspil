# Records what the bord's actions schedule (Table::Surroundings#scheduler) instead of enqueuing jobs, so tests
# run bot turns, next runder, clock ticks and the spil's deadlines (vip's bank window) by hand.
class FakeScheduler
  attr_reader :turns, :deals, :ticks, :deadlines

  def initialize
    @turns = []
    @deals = []
    @ticks = []
    @deadlines = []
  end

  def bot_turn(**turn) = @turns << turn
  def next_runde(**deal) = @deals << deal
  def tick(**tick) = @ticks << tick
  def deadline(**deadline) = @deadlines << deadline
end
