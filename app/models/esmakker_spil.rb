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
#   a bot's turn;
# - the spil's deadline: vip's bank window, which closes when its time runs
#   out (#deadline, #past_deadline, #at_deadline).
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

  # --- The deadline: vip's bank window (ticket 08) ---

  # The spil's deadline after a step at `at` (`intent`, now `round`;
  # `current`, the deadline before it): while vip's bank window is open, its
  # closing time, set to `at` plus the bord's window when it just opened
  # (the vip melder laid away) and again after a bank (after the first bank
  # the melder gets a whole window: Anders, 26 October 2026); nil once the
  # window is closed.
  def deadline(round, rules, intent:, at:, current:)
    return nil unless round.banking?
    return current if current && !intent.is_a?(Esmakker::Bank)

    at + rules.bank_window
  end

  # A bank once the window's time ran out is refused, even before its job
  # has closed the window.
  def past_deadline(intent, deadline_at:, at:)
    :bank_window_closed if intent.is_a?(Esmakker::Bank) && deadline_at && at >= deadline_at
  end

  # When its time runs out, the bank window closes (CloseBankWindow, in the
  # melder's name) and the melder leads the first stik.
  def at_deadline(round)
    return nil unless round.banking?

    [ round.play.melder, Esmakker::CloseBankWindow.new ]
  end

  # What an es-makker spil shows besides what every spil does: the number
  # of runder the spil lasts, the runde being played (a redeal is the same
  # runde again, so it counts the completed runder, while `round_number`
  # counts the round rows dealt; a completed runde still shows as the one
  # being played until the next is dealt), the open bank window, and the
  # score: the totals so far, the seats with the highest total, and every
  # completed runde's result with its points and the running totals after
  # it, for the score sheet (public: the esmakker is known once a runde is
  # over). `spil` answers engine_round, engine_game, engine_rules and
  # deadline_at.
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
    closes_at = spil.deadline_at
    return nil unless spil.engine_round.banking? && closes_at

    { seconds: spil.engine_rules.bank_window, seconds_left: [ closes_at - now, 0 ].max.to_f, closes_at: closes_at.iso8601(3) }
  end

  # A bot's turn in `seat` (Game::BotDecision): the first es-makker bot's
  # intent (Esmakker::Bot, at every level for now), drawing its lots from
  # `random`, from what the seat may see (Esmakker::Round#view_for), and
  # its thought (Esmakker::Bot::Decision). Nil when it has nothing to do
  # (the bank window: it never banks).
  def bot_decision(spil, seat, level:, random:)
    decision = Esmakker::Bot.new(random:).decide(spil.engine_round.view_for(seat))
    decision && Game::BotDecision.new(intent: decision.intent, thought: decision.thought)
  end
end
