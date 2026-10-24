# A clock for TableCommands that only moves when a test says so.
class FakeClock
  attr_reader :now

  def initialize(now = Time.utc(2026, 10, 25, 12))
    @now = now
  end

  def advance(seconds) = @now += seconds
end
