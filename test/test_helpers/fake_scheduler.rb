# Records what TableCommands schedules instead of enqueuing jobs, so tests
# run bot turns, next runder and clock ticks by hand.
class FakeScheduler
  attr_reader :turns, :deals, :ticks

  def initialize
    @turns = []
    @deals = []
    @ticks = []
  end

  def bot_turn(**turn) = @turns << turn
  def next_runde(**deal) = @deals << deal
  def tick(**tick) = @ticks << tick
end
