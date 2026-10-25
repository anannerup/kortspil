# The tur-ur: the clocks of a spil in progress at an open bord (tickets 18 and 19),
# as plain data: given the human seats, when each was last heard from, and
# whom the spil waits for, it says what is due at a moment `now` and when
# the next thing will be. It reads no clock of its own; the bord's actions
# pass the time in (Table::Surroundings#now), so every timer is
# deterministic. The tur-ur's checks run as TurnClockJob (Table#tick).
#
# Rules (PLAN.md "Absence and leaving"):
# - A seat whose heartbeats stop for HEARTBEAT_TIMEOUT seconds is frakoblet
#   from its last heartbeat on, as is one whose connection closes.
# - A frakoblet seat has LIMIT seconds from the moment it was lost to come
#   back, whether or not it is its turn; then it has forladt.
# - A connected seat the spil waits for is warned after WARNING seconds and
#   has forladt after LIMIT. Its wait starts when its turn did, or when it
#   came back, whichever is later. A frakoblet seat the spil waits for has
#   forladt at the earlier of the two deadlines.
# Bots are never in the clock.
class TurnClock
  WARNING = 30
  LIMIT = 60
  HEARTBEAT_TIMEOUT = 10

  # A human seat. `to_act`: the spil waits for it now.
  Seat = Data.define(:seat, :to_act, :heartbeat_at, :connected_at, :disconnected_at, :warned_at) do
    def frakoblet? = !disconnected_at.nil?
  end

  # `turn_started_at`: when the spil started waiting for the seats to act
  # (nil when it waits for nobody).
  def initialize(turn_started_at:, seats:)
    @turn_started_at = turn_started_at
    @seats = seats.index_by(&:seat).freeze
  end

  # A clock that waits for nobody and times nothing (practice tables, a
  # spil that is over).
  def self.none = new(turn_started_at: nil, seats: [])

  # The connected seats not heard from for HEARTBEAT_TIMEOUT, with the
  # moment they were lost (their last heartbeat): [[seat, at], ...].
  def lost(now)
    connected.select { |seat| seat.heartbeat_at && now - seat.heartbeat_at >= HEARTBEAT_TIMEOUT }.map { |seat| [ seat.seat, seat.heartbeat_at ] }
  end

  # The seats that have forladt by `now`.
  def forladt(now) = @seats.values.select { |seat| (deadline = deadline_of(seat)) && deadline <= now }.map(&:seat)

  # The connected seats the spil waits for that are due their warning.
  def to_warn(now)
    connected.select { |seat| (at = warning_at(seat)) && at <= now && deadline_of(seat) > now }.map(&:seat)
  end

  # Seconds until the seat has forladt, if nothing changes; nil when no
  # clock runs for it.
  def seconds_left(seat, now)
    deadline = @seats[seat]&.then { |found| deadline_of(found) }
    deadline && [ deadline - now, 0 ].max.to_f
  end

  # The same clock with the seat frakoblet from `at`, unless it already is.
  def away(seat, at:)
    found = @seats.fetch(seat)
    return self if found.frakoblet?

    TurnClock.new(turn_started_at: @turn_started_at, seats: [ *@seats.except(seat).values, found.with(disconnected_at: at) ])
  end

  # When something is next due: a heartbeat timing out, a warning or a
  # deadline. Nil when nothing is timed.
  def next_check
    times = connected.filter_map { |seat| seat.heartbeat_at && seat.heartbeat_at + HEARTBEAT_TIMEOUT }
    times += connected.filter_map { |seat| warning_at(seat) }
    times += @seats.values.filter_map { |seat| deadline_of(seat) }
    times.min
  end

  private

  def connected = @seats.values.reject(&:frakoblet?)

  def wait_start(seat)
    return nil unless seat.to_act && @turn_started_at

    [ @turn_started_at, seat.connected_at ].compact.max
  end

  def deadline_of(seat)
    start = wait_start(seat)
    [ seat.disconnected_at && seat.disconnected_at + LIMIT, start && start + LIMIT ].compact.min
  end

  # When the seat is to be warned, unless it was warned in this wait already.
  def warning_at(seat)
    start = wait_start(seat)
    return nil if start.nil? || (seat.warned_at && seat.warned_at >= start)

    start + WARNING
  end
end
