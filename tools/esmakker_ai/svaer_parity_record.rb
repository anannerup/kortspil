# Records seeded es-makker spil played by Svær (Esmakker::Svaer) for the
# parity check against the Python Svær (tools/esmakker_ai,
# `python -m esmakker_ai.svaer_parity`). Half the spil have Svær in all four
# seats, the others mix Svær with the first bot (Esmakker::Bot, seeded), at
# least one Svær. Rules are random (EsmakkerParity.random_rules: påhæng
# order, joker and bank toggles, point values, Afkast) and some deals give
# a seat a jernhånd. Nobody banks: the bank window closes at once.
#
# Each line of the gzipped JSON file is one spil:
#
#   { seed, rules, svaer: [seats], runder: [ { dealer, deal, actions,
#     thoughts: { step index => Svær's thought } } ] }
#
# Python replays each runde's log on its own engine and, at every step a
# Svær seat took, asks its Svær for the decision from that seat's
# observation: the action and the thought must be the same.
require "json"
require "zlib"
require_relative "parity_record"

module SvaerParity
  def self.record(path, spil:, seed:)
    random = Random.new(seed)
    counts = { runder: 0, decisions: 0 }
    Zlib::GzipWriter.open(path) do |out|
      spil.times do
        line = play_spil(random.rand(1 << 30), counts)
        out.puts(line.to_json)
      end
    end
    counts
  end

  def self.play_spil(seed, counts)
    random = Random.new(seed)
    rules = EsmakkerParity.random_rules(random)
    svaer = random.rand(2).zero? ? [ 0, 1, 2, 3 ] : Esmakker::Seats::ALL.select { random.rand(2).zero? }
    svaer = [ random.rand(4) ] if svaer.empty?
    first = Esmakker::Bot.new(random: Random.new(random.rand(1 << 30)))
    runder = []
    dealer = random.rand(4)
    (1 + random.rand(3)).times do
      round, thoughts = play_runde(rules, EsmakkerParity.deal_for(random), dealer, svaer, first)
      runder << { dealer:, deal: round.deal_string, actions: round.actions_string, thoughts: }
      counts[:runder] += 1
      counts[:decisions] += thoughts.size
      dealer = round.next_dealer
    end
    { seed:, rules: rules.to_h, svaer:, runder: }
  end

  def self.play_runde(rules, deal, dealer, svaer, first)
    round = Esmakker::Round.new(rules:, deal:, dealer:)
    bot = Esmakker::Svaer.new(rules:)
    thoughts = {}
    until round.complete? || round.redeal?
      if round.banking?
        round = round.apply(round.play.melder, Esmakker::CloseBankWindow.new).round
        next
      end
      seat = round.to_act
      decision = (svaer.include?(seat) ? bot : first).decide(round.view_for(seat))
      thoughts[round.actions.size] = decision.thought if svaer.include?(seat)
      result = round.apply(seat, decision.intent)
      raise "rejected #{decision.intent.inspect} by #{seat}: #{result.reason}" if result.rejected?

      round = result.round
    end
    [ round, thoughts ]
  end
end
