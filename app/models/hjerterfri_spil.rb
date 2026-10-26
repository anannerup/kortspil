# What a hjerterfri spil is at the bord (Game, `game` "hjerterfri"): what
# the spil needs of its card game besides what every spil shares. The
# engine is Hjerterfri; this is where the bord meets it. A spil chooses its
# card game once, from its stored game (Game.card_game), and asks it:
#
# - its rules (Hjerterfri::Rules), the client's actions as intents, and
#   whether a spil lasts the bord's number of runder (no);
# - a runde's row as dealt, and the engine's runde and spil rebuilt from the
#   rows (a completed runde keeps its points per seat);
# - the steps a runde can take (Game#version), whether the seats act at the
#   same time (the bytte), whether a runde is dealt again (never), and the
#   spil's deadline (none);
# - which end of the totals wins (the lowest), the state only hjerterfri
#   shows (the points taken, the score sheet) and a bot's turn.
#
# Es-makker answers the same questions (EsmakkerSpil). Plain Ruby: the
# spil and the rows it is given are read, never saved.
module HjerterfriSpil
  # Versions per runde: four passes, 52 plays, a moon choice, and one step
  # for the deal, so the first state of a runde is newer than the last of
  # the one before.
  STEPS_PER_RUNDE = Hjerterfri::Deal::SEAT_COUNT + (Hjerterfri::Deal::SEAT_COUNT * Hjerterfri::Deal::HAND_SIZE) + 1 + 1

  module_function

  def rules = Hjerterfri::Rules

  def client_intent(action, data) = Hjerterfri::Round.client_intent(action, data)

  # A spil lasts until a seat reaches the end score, not a number of runder.
  def counts_runder? = false

  # The columns of runde `number`'s row, dealt with a fresh shuffle: the
  # deal and the runde's pass direction. The runde before plays no part.
  def deal(number, shuffler:, after: nil)
    { number:, pass_direction: Hjerterfri::PassDirection.for_runde(number).to_s, deal: Hjerterfri::Deal.shuffled(shuffler:).to_s }
  end

  # What is wrong with a runde's row: every hjerterfri runde has a pass
  # direction (:none every fourth).
  def round_errors(row) = row.pass_direction.blank? ? [ [ :pass_direction, :blank ] ] : []

  def engine_round(row, rules)
    Hjerterfri::Round.from_strings(rules:, deal: row.deal, passes: row.passes, plays: row.plays, pass_direction: row.pass_direction, moon_choice: row.moon_choice)
  end

  # The spil lasts until a seat reaches the end score; the bord's number of
  # runder is es-makker's.
  def engine_game(rules:, results:, runder: nil) = Hjerterfri::Game.new(rules:, results:)

  # What the engine's spil keeps of a completed runde: its points per seat.
  def runde_result(round) = round.points

  def steps_per_runde = STEPS_PER_RUNDE

  # Whether the seats act at the same time: in the bytte all four pass
  # together.
  def simultaneous?(round) = round.passing?

  def redeal?(_round) = false

  # No step of hjerterfri has a deadline (the tur-ur is every spil's).
  def deadline(_round, _rules, intent:, at:, current:) = nil
  def past_deadline(_intent, deadline_at:, at:) = nil
  def at_deadline(_round) = nil

  # Points are taken, so the lowest total wins.
  def best_total(totals) = totals.min

  # What a hjerterfri spil shows besides what every spil does: the points
  # each seat has taken in this runde, and the score sheet: completed
  # runder with running totals, who leads (the lowest total) and, once the
  # spil is over, the vindere: the humans among the seats with the lowest
  # total. A bot never wins; a human tied with a bot does (GLOSSARY.md,
  # Vinder). `spil` answers engine_round, engine_game and human_seats.
  def state(spil, now: nil)
    game = spil.engine_game
    totals = game.totals
    leaders = game.results.empty? ? [] : totals.each_index.select { |seat| totals[seat] == totals.min }
    winners = game.winners & spil.human_seats
    { points_taken: spil.engine_round.points_taken, score: { end_score: game.rules.end_score, rows: game.rows, totals:, leaders:, winners: } }
  end

  # A bot's turn in `seat` (Game::BotDecision; Hjerterfri::Bot at
  # `level`, drawing its lots from `random`): it passes, chooses the moon
  # or plays, as the runde asks; its thought is what it did and the rule
  # that decided it (Hjerterfri::Bot::Decision).
  def bot_decision(spil, seat, level:, random:)
    strategy = Hjerterfri::Bot.new(level:, random:)
    round = spil.engine_round
    view = round.view_for(seat)
    game = spil.engine_game
    if round.passing?
      decided = strategy.decide_pass(view)
      return bot_decision_of(:pass, Hjerterfri::Pass.new(cards: decided.choice), decided)
    end
    if round.choosing_moon?
      decided = strategy.decide_moon(seat:, totals: game.totals)
      return bot_decision_of(:moon, Hjerterfri::MoonChoice.new(option: decided.choice), decided)
    end

    decided = strategy.decide_play(view, totals: game.totals, end_score: game.rules.end_score)
    bot_decision_of(:play, Hjerterfri::Play.new(card: decided.choice), decided)
  end

  # The thought: what the bot did (`decision`: "pass", "play", "moon"),
  # what it chose (`choice`: card codes, a card code, a moon option) and
  # the rule that decided it (`reason`).
  def bot_decision_of(kind, intent, decided)
    Game::BotDecision.new(intent:, thought: { decision: kind.to_s, choice: decided.choice, reason: decided.reason.to_s })
  end
end
