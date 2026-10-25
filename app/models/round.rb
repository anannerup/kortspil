# One runde as stored. Hjerterfri: the deal, the passes and the plays as
# space-separated card codes (see the spec's Persistence section), and the
# moon shooter's choice under shooter's choice. Es-makker: the deal (55
# codes: the hands, then the kitty), the kortgiver's seat and the action
# log. The engine's runde (Hjerterfri::Round, Esmakker::Round) is rebuilt
# from these strings, by the spil's game.
class Round < ApplicationRecord
  belongs_to :game

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :deal, presence: true
  validates :pass_direction, presence: true, unless: :esmakker?
  validates :dealer, inclusion: { in: Esmakker::Seats::ALL }, if: :esmakker?

  # Deals runde `number` of a `card_game` spil with a fresh shuffle; call
  # it on a game's rounds. An es-makker runde is dealt by `dealer`.
  def self.deal!(number, shuffler:, card_game: "hjerterfri", dealer: nil)
    return create!(number:, dealer:, deal: Esmakker::Deal.shuffled(shuffler:).to_s) if card_game.to_s == "esmakker"

    create!(number:, pass_direction: Hjerterfri::PassDirection.for_runde(number).to_s, deal: Hjerterfri::Deal.shuffled(shuffler:).to_s)
  end

  def to_engine(rules)
    return Esmakker::Round.from_strings(rules:, deal:, dealer:, actions:) if esmakker?

    Hjerterfri::Round.from_strings(rules:, deal:, passes:, plays:, pass_direction:, moon_choice:)
  end

  private

  def esmakker? = game.esmakker?
end
