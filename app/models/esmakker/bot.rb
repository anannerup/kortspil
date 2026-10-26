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
  class Bot
    MELDING = Melding.parse("9")

    def initialize(random: Random.new)
      @random = random
    end

    # The intent for the seat whose view this is, or nil when it has
    # nothing to do now (not its turn, or the bank window: it never banks).
    def choose(view)
      return nil unless view[:to_act] == view[:seat]

      case view[:phase]
      when :bidding then bid(view[:choices])
      when :choosing_trump then ChooseTrump.new(trump: Trump.parse(pick(view[:choices][:trumps])))
      when :calling_ace then CallAce.new(suit: pick(view[:choices][:aces]))
      when :turning then turn(view[:choices])
      when :discarding, :exchanging then discard(view)
      when :playing then play(view)
      end
    end

    private

    def bid(choices)
      return Bidding::Bid.new(melding: MELDING) if choices[:meldinger].include?(MELDING.to_s)

      Bidding::Pas.new if choices[:pas]
    end

    def turn(choices)
      pick([ (TurnCard.new if choices[:turn_card]), (AcceptTrump.new if choices[:accept_trump]) ].compact)
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
      pick(plays + fordaekt)
    end

    def pick(options) = options.empty? ? nil : options.sample(random: @random)
  end
end
