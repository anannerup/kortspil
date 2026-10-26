# Records seeded es-makker spil from the Ruby engine for the Python port's
# parity check (tools/esmakker_ai, `python -m esmakker_ai.parity`).
#
# Plays seeded spil with random rules (påhæng order, joker and bank
# toggles, bank window, point values with halves) and random legal intents
# through every part of a runde: the meldingsrunde (pas, every melding,
# "det kan jeg selv", gå med, jernhånd claims on dealt jernhånde, all pass),
# trump, called aces, vip turning, the kitty, fordækt, the bank window and
# the sol-exchange. Each line of the gzipped JSON file is one spil:
#
#   { seed, rules, runder: [ { dealer, deal, actions, steps, phase,
#     next_dealer, result }, ... ], totals }
#
# The deal is recorded (55 card codes), so Python need not reproduce Ruby's
# shuffle. Each step holds what the engine said before the action: the
# phase, the seat to act, every seat's legal intents as log tokens (a bank
# only where the bord accepts it; "bankslut" for the melder in the window;
# "kast:N" for a seat that is to lay N cards away) and, per seat, who it
# knows the esmakker to be; and what Round#view_for shows one seat (seat =
# step index mod 4): hand, card counts, the kitty, the stik on the table,
# fordækt, the esmakker if known.
require "json"
require "zlib"

module EsmakkerParity
  POINT_VALUES = [ 0.5, 1, 1.5, 2, 2.5, 3, 4 ].freeze
  NUMBER_CARDS = Esmakker::Card.deck.select { |card| !card.joker? && %w[2 3 4 5 6 7 8 9 T].include?(card.rank) }.freeze

  def self.record(path, spil:, seed:)
    random = Random.new(seed)
    runder = 0
    Zlib::GzipWriter.open(path) do |out|
      spil.times do
        line = play_spil(random.rand(1 << 30))
        runder += line[:runder].size
        out.puts(line.to_json)
      end
    end
    runder
  end

  def self.play_spil(seed)
    random = Random.new(seed)
    rules = random_rules(random)
    runder = []
    results = []
    dealer = random.rand(4)
    count = 1 + random.rand(4)
    while results.size < count && runder.size < count + 20
      round = play_runde(rules, deal_for(random), dealer, random)
      runder << record_runde(round)
      results << round.points if round.complete?
      dealer = round.next_dealer
    end
    { seed:, rules: rules.to_h, runder:, totals: Esmakker::Scoring.sum(results) }
  end

  def self.random_rules(random)
    return Esmakker::Rules.standard if random.rand(3).zero?

    points = if random.rand(2).zero?
      Esmakker::Points.standard
    else
      values = [ *Esmakker::Points::FACTORS, *Esmakker::Points::AMOUNTS ].to_h { |key| [ key, POINT_VALUES.sample(random:) ] }
      Esmakker::Points.from_h(stakes: Esmakker::Points::NUMBERS.to_h { |number| [ number, POINT_VALUES.sample(random:) ] }, **values)
    end
    Esmakker::Rules.new(pahaeng_order: Esmakker::Rules::PAHAENG.shuffle(random:), joker_trumpable: random.rand(2).zero?,
                        esmakker_banks_first: random.rand(2).zero?, bank_window: random.rand(5..10), points:)
  end

  # Mostly shuffled deals; one in twenty gives a random seat a jernhånd.
  def self.deal_for(random)
    return Esmakker::Deal.shuffled(shuffler: Random.new(random.rand(1 << 30))) unless random.rand(20).zero?

    iron = NUMBER_CARDS.sample(Esmakker::Deal::HAND_SIZE, random:)
    rest = (Esmakker::Card.deck - iron).shuffle(random:)
    hands = rest.first(39).each_slice(13).to_a.insert(random.rand(4), iron)
    Esmakker::Deal.new(hands:, kitty: rest.last(3))
  end

  def self.play_runde(rules, deal, dealer, random)
    round = Esmakker::Round.new(rules:, deal:, dealer:)
    steps = []
    until round.complete? || round.redeal?
      steps << step(round, steps.size % Esmakker::SEAT_COUNT)
      seat, intent = choose(round, random)
      result = round.apply(seat, intent)
      raise "rejected #{intent.inspect} by #{seat}: #{result.reason}" if result.rejected?

      round = result.round
    end
    StepsRound.new(round, steps)
  end

  StepsRound = Struct.new(:round, :steps) do
    def complete? = round.complete?
    def points = round.points
    def next_dealer = round.next_dealer
  end

  def self.record_runde(played)
    round = played.round
    { dealer: round.dealer, deal: round.deal_string, actions: round.actions_string, steps: played.steps,
      phase: round.phase, next_dealer: round.next_dealer, result: round.result&.to_h }
  end

  def self.step(round, view_seat)
    legal = Esmakker::Seats::ALL.to_h { |seat| [ seat, legal_tokens(round, seat) ] }.reject { |_seat, tokens| tokens.empty? }
    play = round.play
    known = Esmakker::Seats::ALL.map { |seat| play.is_a?(Esmakker::Play) && play.esmakker_known?(seat) ? (play.esmakker || -1) : nil }
    { phase: round.phase, to_act: round.to_act, legal:, known:, view: view(round, view_seat) }
  end

  # What Round#view_for shows one seat (the seats take turns step by step),
  # the parts the Python observation must agree with.
  def self.view(round, seat)
    view = round.view_for(seat)
    play = view[:play] || {}
    { seat:, hand: view[:hand], card_counts: view[:card_counts], kitty_count: view[:kitty_count],
      esmakker: play[:esmakker], selvmakker: play[:selvmakker] || false, turned: play[:turned] || [],
      kitty_cards: play[:kitty_cards] || [], discarded: play[:discarded] || [],
      current_trick: play[:current_trick] || [], last_trick: play[:last_trick] || [],
      fordaekt: play[:fordaekt], open_hand: play[:open_hand] }
  end

  def self.legal_tokens(round, seat)
    intents = round.phase == :bidding ? round.bidding.legal_intents(seat) : round.play.legal_intents(seat)
    if round.banking?
      intents = [ *intents, Esmakker::CloseBankWindow.new ].select { |intent| round.apply(seat, intent).accepted? }
    end
    tokens = intents.map { |intent| Esmakker::Round.token(intent) }.sort
    tokens << "kast:#{discard_size(round)}" if %i[discarding exchanging].include?(round.phase) && seat == round.to_act
    tokens
  end

  def self.discard_size(round) = round.phase == :discarding ? Esmakker::Deal::KITTY_SIZE : round.play.discard_size

  def self.choose(round, random)
    case round.phase
    when :bidding then choose_bid(round, random)
    when :banking then choose_bank(round, random)
    when :discarding then [ round.to_act, Esmakker::Discard.new(cards: round.play.hand(round.to_act).sample(3, random:)) ]
    when :exchanging then [ round.to_act, exchange(round, random) ]
    else
      seat = round.to_act
      intents = round.play.legal_intents(seat)
      fordaekt = intents.grep(Esmakker::LayFordaekt)
      # Fordækt is rare (the melder must be void in the ace's suit): take it when offered, mostly.
      [ seat, (fordaekt.any? && random.rand(4).positive? ? fordaekt : intents).sample(random:) ]
    end
  end

  def self.choose_bid(round, random)
    claimers = Esmakker::Seats::ALL.select { |seat| round.bidding.legal_intents(seat).include?(Esmakker::Bidding::ClaimJernhaand.new) }
    return [ claimers.sample(random:), Esmakker::Bidding::ClaimJernhaand.new ] if claimers.any? && random.rand(3).zero?

    seat = round.to_act
    legal = round.bidding.legal_intents(seat)
    med = legal.include?(Esmakker::Bidding::GaaMed.new)
    roll = random.rand
    return [ seat, Esmakker::Bidding::GaaMed.new ] if med && roll < 0.25
    if legal.include?(Esmakker::Bidding::DetKanJegSelv.new)
      return [ seat, roll < 0.6 ? Esmakker::Bidding::DetKanJegSelv.new : Esmakker::Bidding::Pas.new ]
    end

    bids = legal.grep(Esmakker::Bidding::Bid)
    return [ seat, Esmakker::Bidding::Pas.new ] if bids.empty? || roll < 0.45

    [ seat, random.rand(2).zero? ? bids.first(3).sample(random:) : bids.sample(random:) ]
  end

  def self.choose_bank(round, random)
    melder = round.play.melder
    bankers = Esmakker::Seats::ALL.select { |seat| round.apply(seat, Esmakker::Bank.new).accepted? }
    return [ melder, Esmakker::CloseBankWindow.new ] if bankers.empty? || random.rand(2).zero?

    [ bankers.sample(random:), Esmakker::Bank.new ]
  end

  # Lays some of the kitty back (all of it now and then) and the rest from
  # the seat's own hand.
  def self.exchange(round, random)
    kitty = round.play.kitty
    own = round.play.hand(round.to_act) - kitty
    back = random.rand(3).zero? ? kitty.size : random.rand(kitty.size + 1)
    Esmakker::Discard.new(cards: (kitty.sample(back, random:) + own.sample(kitty.size - back, random:)).shuffle(random:))
  end
end
