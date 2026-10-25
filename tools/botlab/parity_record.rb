# Records the Ruby bots' decisions for `botlab parity` (see README.md).
# Plays seeded spil with bots of random levels and random rules, and writes
# every decision as one JSON line: passes, plays (with the view the bot
# saw, the totals and the end score) and moon choices, plus each whole
# runde so the Rust engine can replay it. Variation is off: a random whose
# rand(n) is 0 makes Array#sample pick the chosen card.
module BotParity
  class NoVariation
    def rand(*) = 0
  end

  VIEW_KEYS = %i[seat hand legal_moves current_trick tricks rules hearts_broken pass_direction own_pass received_cards card_counts].freeze

  def self.record(path, spil:, seed:)
    random = Random.new(seed)
    decisions = 0
    File.open(path, "w") do |out|
      write = ->(line) { out.puts(line.to_json); decisions += 1 }
      spil.times { play_spil(random, write) }
    end
    decisions
  end

  def self.play_spil(random, write)
    rules = Hjerterfri::Rules.new(end_score: [ 50, 100 ].sample(random:), queen_breaks_hearts: random.rand(2).zero?,
                                  jack_of_diamonds_minus_ten: random.rand(2).zero?, shooters_choice: random.rand(2).zero?)
    levels = Array.new(Hjerterfri::Deal::SEAT_COUNT) { Hjerterfri::Bot::LEVELS.sample(random:) }
    bots = levels.map { |level| Hjerterfri::Bot.new(level:, random: NoVariation.new) }
    # Some spil start part-way, near the end score; some give the bots no totals.
    start = random.rand(2).zero? ? [] : [ Array.new(Hjerterfri::Deal::SEAT_COUNT) { random.rand(rules.end_score) } ]
    game = Hjerterfri::Game.new(rules:, results: start)
    scored = random.rand(5).positive?
    shuffler = Random.new(random.rand(1 << 30))
    game = game.add(play_runde(game, rules, levels, bots, shuffler, scored, write)) until game.over?
  end

  def self.play_runde(game, rules, levels, bots, shuffler, scored, write)
    totals = scored ? game.totals : nil
    end_score = scored ? rules.end_score : nil
    round = Hjerterfri::Round.new(rules:, deal: Hjerterfri::Deal.shuffled(shuffler:), pass_direction: game.next_pass_direction)
    if round.passing?
      (0...Hjerterfri::Deal::SEAT_COUNT).each do |seat|
        hand = round.view_for(seat)[:hand]
        pass = bots[seat].choose_pass(hand)
        write.({ kind: "pass", level: levels[seat], hand:, choice: pass })
        round = round.apply(seat, Hjerterfri::Pass.new(cards: pass)).round
      end
    end

    until round.complete?
      seat = round.to_act
      if round.choosing_moon?
        choice = bots[seat].choose_moon(seat:, totals: game.totals)
        write.({ kind: "moon", seat:, totals: game.totals, choice: })
        round = round.apply(seat, Hjerterfri::MoonChoice.new(option: choice)).round
      else
        view = round.view_for(seat).slice(*VIEW_KEYS)
        card = bots[seat].choose_play(view, totals:, end_score:)
        write.({ kind: "play", level: levels[seat], view:, totals:, end_score:, choice: card })
        round = round.apply(seat, Hjerterfri::Play.new(card:)).round
      end
    end

    write.({ kind: "runde", levels:, rules: rules.to_h, deal: round.deal.hands.map { |hand| hand.map(&:to_s) },
             pass_direction: round.pass_direction, passes: round.passes.slots.map { |slot| slot&.map(&:to_s) },
             plays: round.plays.map(&:to_s), totals:, end_score:, game_totals: game.totals, points: round.points })
    round.points
  end
end
