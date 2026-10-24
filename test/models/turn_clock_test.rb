require "test_helper"

# TurnClock is plain data in, decisions out: no database, no clock.
class TurnClockTest < ActiveSupport::TestCase
  T0 = Time.utc(2026, 10, 25, 12)

  test "a connected seat on its turn: warned from 30 s, forladt at 60 s" do
    clock = clock_with(seat(0, to_act: true, heartbeat_at: T0 + 25))

    assert_empty clock.to_warn(T0 + 29)
    assert_equal [ 0 ], clock.to_warn(T0 + 30)
    assert_empty clock.forladt(T0 + 59)
    assert_equal [ 0 ], clock.forladt(T0 + 60)
    assert_equal 31.0, clock.seconds_left(0, T0 + 29)
  end

  test "a seat warned in this wait is not warned again; one warned in an earlier wait is" do
    assert_empty clock_with(seat(0, to_act: true, heartbeat_at: T0 + 30, warned_at: T0 + 30)).to_warn(T0 + 40)
    assert_equal [ 0 ], clock_with(seat(0, to_act: true, heartbeat_at: T0 + 30, warned_at: T0 - 5)).to_warn(T0 + 40)
  end

  test "heartbeats lost for 10 s, from the last one" do
    clock = clock_with(seat(0, to_act: false, heartbeat_at: T0), seat(1, to_act: false, heartbeat_at: T0 + 5))

    assert_empty clock.lost(T0 + 9)
    assert_equal [ [ 0, T0 ] ], clock.lost(T0 + 10)
  end

  test "frakoblet: 60 s from the loss whether or not it is the seat's turn, and the earlier deadline on its turn" do
    away = seat(0, to_act: false, heartbeat_at: T0, disconnected_at: T0 + 20)
    assert_equal [ 0 ], clock_with(away).forladt(T0 + 80)
    assert_equal 60.0, clock_with(away).seconds_left(0, T0 + 20)
    assert_empty clock_with(away).to_warn(T0 + 80)

    on_turn = away.with(to_act: true)
    assert_equal 40.0, clock_with(on_turn).seconds_left(0, T0 + 20), "the turn began at T0"
  end

  test "coming back starts the wait on the turn again" do
    back = seat(0, to_act: true, heartbeat_at: T0 + 50, connected_at: T0 + 50)

    assert_empty clock_with(back).forladt(T0 + 60)
    assert_equal 60.0, clock_with(back).seconds_left(0, T0 + 50)
  end

  test "the next check is the earliest of heartbeat timeouts, warnings and deadlines" do
    clock = clock_with(seat(0, to_act: true, heartbeat_at: T0 + 28), seat(1, to_act: false, heartbeat_at: T0, disconnected_at: T0))

    assert_equal T0 + 30, clock.next_check
    assert_nil TurnClock.none.next_check
  end

  test "away marks a seat frakoblet from a moment, unless it already is" do
    clock = clock_with(seat(0, to_act: false, heartbeat_at: T0))

    assert_equal 60.0, clock.away(0, at: T0 + 5).seconds_left(0, T0 + 5)
    assert_nil clock.seconds_left(0, T0 + 5)
  end

  private

  def clock_with(*seats) = TurnClock.new(turn_started_at: T0, seats:)

  def seat(number, to_act:, heartbeat_at:, connected_at: nil, disconnected_at: nil, warned_at: nil)
    TurnClock::Seat.new(seat: number, to_act:, heartbeat_at:, connected_at:, disconnected_at:, warned_at:)
  end
end
