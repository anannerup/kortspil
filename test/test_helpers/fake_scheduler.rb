# Records what TableCommands schedules instead of enqueuing jobs, so tests
# run bot turns and next runder by hand.
class FakeScheduler
  attr_reader :turns, :deals

  def initialize
    @turns = []
    @deals = []
  end

  def bot_turn(**turn) = @turns << turn
  def next_runde(**deal) = @deals << deal
end
