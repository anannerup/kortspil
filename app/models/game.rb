# A spil at a table: the card game (`game`, the table's: hjerterfri or
# es-makker), the rules it is played with, who sat where when it started,
# and its runder. Who sits where now is the table's Seating.
#
# The engine state is the game's: Hjerterfri::Round and Hjerterfri::Game,
# or Esmakker::Round and Esmakker::Game, which answer the same questions
# here (the seats to act, the steps taken, the columns to store). An
# es-makker spil lasts the table's number of runder.
#
# A spil gives its engine state itself (see the spec's Persistence
# section): the engine's runde and spil (`engine_round`, Hjerterfri::Round,
# and `engine_game`, Hjerterfri::Game) are rebuilt from the round rows once
# per load, each stored runde replayed once, and kept until the row is
# reloaded (as #with_lock does). #apply and #deal_next! save to the rows and
# move the engine state on with them. The bord's actions (Table) load the
# spil under its row lock, ask it what is due, and save passes, plays and
# deals through it. What each seat may see is Game::State.
#
# A finished spil keeps its final totals in `final_scores`. A spil afbrudt
# (abandoned) because its last human left keeps the totals of its completed
# runder there and records that player in `forfeited_by`.
#
# `seats` is the snapshot taken at the start and never changes: four
# entries in seat order, { "kind" => "human", "user_id" => 7 } or
# { "kind" => "bot", "name" => "Bot 1", "level" => "mellem" }. Later
# changes are appended to `seat_log` as { seat, from, to, level, at_play }
# (Table::Seating#take_over!), so a replay knows who held each seat, and a
# bot at which level, at every step. Spil stored before levels were
# recorded have no "level": the level is unknown, not guessed.
#
# The stored result is neutral: the final totals per seat, human or bot,
# and from them the seats with the lowest total (#lowest_seats). The
# glossary's rules are applied when the result is shown (GLOSSARY.md:
# Forlade, Vinder, Afbrudt): every player who forlod the spil lost it,
# whatever their points (#forladt_ids). Once it is finished, the vindere
# are the humans still in their seats among the lowest; a human tied with
# a bot wins, a bot never does (#winner_ids, Game::State#score). A spil
# abandoned because its last human left is afbrudt: no vinder.
class Game < ApplicationRecord
  include State

  SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT
  # Versions per runde: four passes, 52 plays, a moon choice, and one step
  # for the deal, so the first state of a runde is newer than the last of
  # the one before.
  STEPS_PER_RUNDE = SEAT_COUNT + (SEAT_COUNT * Hjerterfri::Deal::HAND_SIZE) + 1 + 1

  belongs_to :table
  belongs_to :forfeited_by, class_name: "User", optional: true
  has_many :rounds, -> { order(:number) }, dependent: :destroy, inverse_of: :game

  enum :status, { in_progress: "in_progress", finished: "finished", abandoned: "abandoned" }, validate: true

  validates :game, inclusion: { in: GameRules::GAMES }
  validate :four_seats

  # A new spil at the table with whoever sits there now, played with
  # `rules` (GameRules); runde 1 is dealt (at es-makker by the first
  # kortgiver, Esmakker::Seats).
  def self.start!(table:, rules:, shuffler:)
    game = table.games.create!(game: table.game, rules: rules.to_h, seats: table.seating.snapshot)
    game.rounds.deal!(1, shuffler:, card_game: game.game, dealer: (Esmakker::Seats::FIRST_DEALER if game.esmakker?))
    game
  end

  def esmakker? = game == "esmakker"

  # Loads the runder once per load of the spil.
  def current_round = rounds.to_a.last

  # Rereads the row and forgets the engine state built from it.
  def reload(*)
    super.tap { forget_engine_state }
  end

  # Who holds each seat now: the start snapshot with the seat_log applied.
  def holders
    seats.each_with_index.map do |start, seat|
      taken = seat_log.reverse.find { |entry| entry["seat"] == seat }
      taken ? { "kind" => "bot", "name" => taken["to"], "level" => taken["level"] }.compact : start
    end
  end

  # The seats a human holds now.
  def human_seats = holders.each_with_index.filter_map { |holder, seat| seat if holder["kind"] == "human" }

  # The players who forlod the spil: a bot took their seat, or they were
  # the last human and left. Each of them lost it.
  def forladt_ids = [ *seat_log.map { |entry| entry["from"] }, forfeited_by_id ].compact.uniq

  # The seats, human or bot, with the lowest final total of a finished
  # spil; ties share. What happened, before any rule about who may win.
  def lowest_seats
    return [] unless finished?

    final_scores.each_index.select { |seat| final_scores[seat] == final_scores.min }
  end

  # The seats with the best final total of a finished spil: the lowest at
  # hjerterfri, the highest at es-makker (points are won there); ties share.
  def best_seats
    return lowest_seats unless esmakker?
    return [] unless finished?

    final_scores.each_index.select { |seat| final_scores[seat] == final_scores.max }
  end

  # The vindere of a finished spil, as user ids: the humans among the
  # best seats (see above).
  def winner_ids
    now = holders
    (best_seats & human_seats).map { |seat| now[seat]["user_id"] }
  end

  # The engine's rules config (GameRules). Keys missing from the stored
  # snapshot take the standard value, so older games keep loading when
  # toggles are added.
  def engine_rules = GameRules.from_stored(rules, game:)

  # --- The engine state ---

  def engine_round = @engine_round ||= current_round.to_engine(engine_rules)

  def engine_game
    @engine_game ||= begin
      results = engine_round.complete? ? [ *earlier_results, runde_result(engine_round) ] : earlier_results
      if esmakker?
        Esmakker::Game.new(rules: engine_round.rules, runder: table.runder, results:)
      else
        Hjerterfri::Game.new(rules: engine_round.rules, results:)
      end
    end
  end

  # Who sits where at the bord, read once per load. Set it to the seating
  # a change returned (a bot took a seat over, the tur-ur marked a seat).
  def seating = @seating ||= table.seating

  def seating=(seating)
    @seating = seating
    @took_over_from = nil
  end

  # Grows with every step in the spil (a pass, play or moon choice; an
  # es-makker action) and every deal, so clients can ignore a state that
  # arrives after a newer one, and a scheduled bot turn can tell it is
  # stale.
  def version = runde_base + engine_round.steps

  # The seats that are to act now (the engine's runde says which).
  def seats_to_act
    return [] unless in_progress?

    engine_round.seats_to_act
  end

  def bots_to_act = seats_to_act.select { |seat| seating.occupants.fetch(seat).bot? }

  # The tur-ur of the human seats (TurnClock): only for a spil in progress
  # at an open bord. Practice tables wait for their player as long as it
  # takes.
  def turn_clock
    return TurnClock.none unless in_progress? && table.open?

    to_act = seats_to_act
    seats = seating.occupants.select(&:human?).map do |occupant|
      TurnClock::Seat.new(seat: occupant.seat, to_act: to_act.include?(occupant.seat), **occupant.to_h.slice(:heartbeat_at, :connected_at, :disconnected_at, :warned_at))
    end
    TurnClock.new(turn_started_at:, seats:)
  end

  # The spil starts waiting for the seats to act now, at `at`: after a deal,
  # a play or a moon choice, and when the pass is complete.
  def turn_started!(at:) = update!(turn_started_at: at)

  # Whether a bot turn scheduled at `scheduled_version` should still be
  # taken. A pass only needs the runde to be the one it was scheduled in; a
  # play needs nothing to have happened since.
  def bot_turn_due?(seat, scheduled_version)
    return false unless bots_to_act.include?(seat)

    engine_round.passing? ? scheduled_version >= runde_base : scheduled_version == version
  end

  # Applies a pass, play or moon choice (an es-makker intent) for the seat
  # and saves it; the
  # runde that completes the spil finishes it. Returns the engine's result:
  # rejected with its reason (and nothing changed), or not.
  def apply(seat, intent)
    result = engine_round.apply(seat, intent)
    return result if result.rejected?

    current_round.update!(result.round.stored)
    @engine_round = result.round
    @engine_game = nil
    update!(status: :finished, final_scores: engine_game.totals) if engine_game.over?
    result
  end

  # Keeps the bank window's closing time (`bank_closes_at`, ticket 08) in
  # step with the runde: set to `at` plus the bord's window when vip's trump
  # was just named, cleared once the window is closed.
  def track_bank_window!(at:)
    if banking?
      update!(bank_closes_at: at + engine_rules.bank_window) unless bank_closes_at
    elsif bank_closes_at
      update!(bank_closes_at: nil)
    end
  end

  # Whether vip's bank window is open (an es-makker runde, Esmakker::Round#banking?).
  def banking? = esmakker? && engine_round.banking?

  # Whether a bank at `at` comes after the bank window's time ran out (its
  # job may not have closed it yet).
  def bank_window_over?(at) = !bank_closes_at.nil? && at >= bank_closes_at

  # The number of the round row to deal next: once this runde is complete
  # and the spil goes on, or when it is to be dealt again (#redeal?).
  # Otherwise nil.
  def next_runde_number = in_progress? && (engine_round.complete? || redeal?) ? current_round.number + 1 : nil

  # Whether the current runde is to be dealt again (an es-makker
  # meldingsrunde where everybody passed or a jernhånd was claimed). The
  # redeal is the next round row, by the dealer the runde names
  # (Esmakker::Round#next_dealer); it is the same runde of the spil, as
  # only completed runder count (Esmakker::Game).
  def redeal? = esmakker? && engine_round.redeal?

  def deal_next!(shuffler:)
    number = next_runde_number
    raise ArgumentError, "no runde is due" unless number

    results = engine_game.results
    rounds.deal!(number, shuffler:, card_game: game, dealer: (engine_round.next_dealer if esmakker?))
    rounds.reset
    @earlier_results = results
    @engine_round = @engine_game = nil
  end

  # The last human left the spil in progress: it is afbrudt (abandoned)
  # with the totals of its completed runder and the leaver recorded, so it
  # counts as their loss.
  def abandon!(forfeited_by:)
    update!(status: :abandoned, final_scores: engine_game.totals, forfeited_by:) if in_progress?
  end

  private

  def runde_base = (current_round.number - 1) * (esmakker? ? Esmakker::Round::MAX_STEPS : STEPS_PER_RUNDE)

  # The results of the completed runder before the current one, each
  # replayed once per load.
  def earlier_results
    @earlier_results ||= rounds.to_a[0...-1].map { |row| row.to_engine(engine_rules) }.select(&:complete?).map { |round| runde_result(round) }
  end

  # What the engine's spil keeps of a completed runde: hjerterfri its
  # points per seat, es-makker its RundeResult.
  def runde_result(round) = esmakker? ? round.result : round.points

  def forget_engine_state
    @engine_round = @engine_game = @earlier_results = @seating = @took_over_from = nil
  end

  def four_seats
    errors.add(:seats, "must hold #{Hjerterfri::Deal::SEAT_COUNT} seats") unless seats.size == Hjerterfri::Deal::SEAT_COUNT
  end
end
