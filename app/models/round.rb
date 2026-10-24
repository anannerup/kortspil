# One runde as stored: the deal, the passes and the plays as space-separated
# card codes (see the spec's Persistence section), and the moon shooter's
# choice under shooter's choice. The engine's Hjerterfri::Round is rebuilt
# from these strings.
class Round < ApplicationRecord
  belongs_to :game

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :deal, :pass_direction, presence: true

  # Deals runde `number` with a fresh shuffle; call it on a game's rounds.
  def self.deal!(number, shuffler:)
    create!(number:, pass_direction: Hjerterfri::PassDirection.for_runde(number).to_s, deal: Hjerterfri::Deal.shuffled(shuffler:).to_s)
  end

  def to_engine(rules)
    Hjerterfri::Round.from_strings(rules:, deal:, passes:, plays:, pass_direction:, moon_choice:)
  end
end
