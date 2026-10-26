# What an es-makker spil is at the bord (Game, `game` "esmakker"): the
# same questions HjerterfriSpil answers for hjerterfri, for the Esmakker
# engine. A spil lasts the bord's number of runder.
#
# - its rules (Esmakker::Rules), the client's actions as intents, and
#   whether a spil lasts the bord's number of runder (yes);
# - a runde's row as dealt (by the kortgiver: the first, Esmakker::Seats,
#   then the one the runde before names, Esmakker::Round#next_dealer), and
#   the engine's runde and spil rebuilt from the rows (a completed runde
#   keeps its RundeResult);
# - the steps a runde can take, whether the seats act at the same time
#   (never), whether a runde is dealt again (everybody passed, a jernhånd);
# - which end of the totals wins (the highest: points are won), the state
#   only es-makker shows (the runder, the score sheet, the bank window) and
#   a bot's turn.
#
# Plain Ruby: the spil and the rows it is given are read, never saved.
module EsmakkerSpil
  module_function

  def rules = Esmakker::Rules

  def client_intent(action, data) = Esmakker::Round.client_intent(action, data)

  # A spil lasts the bord's number of runder (TableRules).
  def counts_runder? = true

  # The columns of runde `number`'s row, dealt with a fresh shuffle by the
  # kortgiver: the first one, or the one the runde `after` names (a redeal
  # is the next row too).
  def deal(number, shuffler:, after: nil)
    { number:, dealer: after ? after.next_dealer : Esmakker::Seats::FIRST_DEALER, deal: Esmakker::Deal.shuffled(shuffler:).to_s }
  end

  # What is wrong with a runde's row: its kortgiver is one of the seats.
  def round_errors(row) = Esmakker::Seats::ALL.include?(row.dealer) ? [] : [ [ :dealer, :inclusion ] ]

  def engine_round(row, rules) = Esmakker::Round.from_strings(rules:, deal: row.deal, dealer: row.dealer, actions: row.actions)

  def engine_game(rules:, results:, runder:) = Esmakker::Game.new(rules:, runder:, results:)

  # What the engine's spil keeps of a completed runde: its RundeResult
  # (SolResult).
  def runde_result(round) = round.result

  def steps_per_runde = Esmakker::Round::MAX_STEPS

  # One seat acts at a time.
  def simultaneous?(_round) = false

  # Whether the runde is to be dealt again (everybody passed, a jernhånd).
  def redeal?(round) = round.redeal?

  # Points are won, so the highest total wins.
  def best_total(totals) = totals.max

  # Whether vip's bank window is open (Esmakker::Round#banking?).
  def banking?(round) = round.banking?

  # What an es-makker spil shows besides what every spil does: the number
  # of runder the spil lasts, the runde being played (a redeal is the same
  # runde again, so it counts the completed runder, while `round_number`
  # counts the round rows dealt; a completed runde still shows as the one
  # being played until the next is dealt), the open bank window, and the
  # score: the totals so far, the seats with the highest total, and every
  # completed runde's result with its points and the running totals after
  # it, for the score sheet (public: the esmakker is known once a runde is
  # over). `spil` answers engine_round, engine_game, engine_rules and
  # bank_closes_at.
  def state(spil, now:)
    game = spil.engine_game
    completed = game.results.size - (spil.engine_round.complete? ? 1 : 0)
    runde = [ completed + 1, game.runder ].min
    results = game.results.zip(game.running_totals).map { |result, totals| result.to_h.merge(totals:) }
    { runder: game.runder, runde:, bank_window: bank_window(spil, now),
      score: { totals: game.totals, leaders: game.leaders, results: } }
  end

  # The open bank window for the countdown (ticket 08): its length and the
  # seconds left at `now` (the client counts down from receiving it, so
  # its clock does not matter). Nil when no window is open.
  def bank_window(spil, now)
    closes_at = spil.bank_closes_at
    return nil unless spil.engine_round.banking? && closes_at

    { seconds: spil.engine_rules.bank_window, seconds_left: [ closes_at - now, 0 ].max.to_f, closes_at: closes_at.iso8601(3) }
  end

  # A bot's turn in `seat`: no es-makker bots in v1, so a bot that took
  # over a seat does what the runde gives as its default
  # (Esmakker::Round#default_intent: pas, clubs, the first ace, at vip the
  # first card turned as trump, the kitty laid back, the first legal card),
  # so the spil is not stuck on it; what it should do is ticket 11's.
  def bot_intent(spil, seat, level: nil, random: nil) = spil.engine_round.default_intent(seat)
end
