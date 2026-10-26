module Esmakker
  # The first es-makker bot (docs/bots/esmakker-strategy.md §2, decided
  # with Anders): a bot without logic, so es-makker can be played with bots
  # before the trained ones exist. Every level (Let, Mellem, Svær) plays
  # it for now.
  #
  # - In the meldingsrunde it melder 9 when 9 is a melding it may bid,
  #   otherwise pas. It never goes with on a sol-melding, never says "det
  #   kan jeg selv" and never claims a jernhånd.
  # - It never banks.
  # - Everything else (trump or trumfløs, the called ace, turning the
  #   kitty at vip, the cards laid away, fordækt, the card to play) is a
  #   legal choice drawn at random with the injected `random:`, so a seeded
  #   bot is deterministic.
  #
  # It reads only the seat's view (Round#view_for): its own hand and what
  # it may choose now, never another seat's cards.
  #
  # Each choice comes with what the bot thought (#decide: a Decision), for
  # "Vis kort" (docs/bots/esmakker-strategy.md §5): the decision, why, and
  # its estimates for the runde. The thought is built from the choice and
  # never changes it: #choose is #decide's intent.
  class Bot
    MELDING = Melding.parse("9")

    # An intent and the thought behind it, a hash:
    # - `decision`: what the bot does ("bid", "pas", "choose_trump",
    #   "call_ace", "turn_card", "accept_trump", "discard", "lay_fordaekt",
    #   "play");
    # - `reason`: why ("fixed_melding": it melder its one melding;
    #   "not_legal": that melding may not be bid now; "random": a legal
    #   choice drawn at random);
    # - `melding`: the melding the reason is about (the first bot's 9), or nil;
    # - `expect`: what it expects of the runde, each nil while it does not
    #   know (the first bot never does, beyond the melding it bids): the
    #   melding it means to play (`melding`), the stik it and its makker
    #   take (`stik: { self:, makker: }`), the seat it guesses is makker
    #   (`makker`) and the runde's points for it (`points`).
    Decision = Data.define(:intent, :thought)

    def initialize(random: Random.new)
      @random = random
    end

    # The intent for the seat whose view this is, or nil when it has
    # nothing to do now (not its turn, or the bank window: it never banks).
    def choose(view) = decide(view)&.intent

    # The intent (#choose) with the thought behind it, or nil.
    def decide(view)
      return nil unless view[:to_act] == view[:seat]

      case view[:phase]
      when :bidding then bid(view[:choices])
      when :choosing_trump then random(:choose_trump, ChooseTrump.new(trump: Trump.parse(pick(view[:choices][:trumps]))))
      when :calling_ace then random(:call_ace, CallAce.new(suit: pick(view[:choices][:aces])))
      when :turning then turn(view[:choices])
      when :discarding, :exchanging then random(:discard, discard(view))
      when :playing then play(view)
      end
    end

    private

    def bid(choices)
      return decision(Bidding::Bid.new(melding: MELDING), :bid, :fixed_melding, expect: MELDING.to_s) if choices[:meldinger].include?(MELDING.to_s)

      decision(Bidding::Pas.new, :pas, :not_legal) if choices[:pas]
    end

    def turn(choices)
      intent = pick([ (TurnCard.new if choices[:turn_card]), (AcceptTrump.new if choices[:accept_trump]) ].compact)
      random(intent.is_a?(AcceptTrump) ? :accept_trump : :turn_card, intent)
    end

    # Lays away as many cards as the play asks (three after taking the
    # kitty; at a sol-melding as many as it took up), drawn from its hand.
    def discard(view)
      size = view[:play][:discard_size]
      Discard.new(cards: view[:hand].sample(size, random: @random).map { |code| Card.parse(code) })
    end

    # A card it may play, or (the melder before the first stik) a card it
    # may lay fordækt: one of them at random.
    def play(view)
      plays = view[:play][:legal_moves].map { |code| PlayCard.new(card: Card.parse(code)) }
      fordaekt = view[:choices][:fordaekt].map { |code| LayFordaekt.new(card: Card.parse(code)) }
      intent = pick(plays + fordaekt)
      random(intent.is_a?(LayFordaekt) ? :lay_fordaekt : :play, intent)
    end

    def pick(options) = options.empty? ? nil : options.sample(random: @random)

    def random(kind, intent) = decision(intent, kind, :random)

    # The intent with its thought (Decision); nil without an intent.
    # `expect`: the melding it means to play, the only estimate the first
    # bot makes.
    def decision(intent, kind, reason, expect: nil)
      return nil unless intent

      melding = reason == :random ? nil : MELDING.to_s
      Decision.new(intent:, thought: { decision: kind.to_s, reason: reason.to_s, melding:,
                                       expect: { melding: expect, stik: { self: nil, makker: nil }, makker: nil, points: nil } })
    end
  end
end
