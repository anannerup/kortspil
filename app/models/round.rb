# One runde as stored: the deal, the passes and the plays as space-separated
# card codes (see the spec's Persistence section). The engine's
# Hjerterfri::Round is rebuilt from these strings.
class Round < ApplicationRecord
  belongs_to :game

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :deal, :pass_direction, presence: true

  def plays_made = plays.split.size
  def passes_made = Hjerterfri::Passes.parse(passes).passed_seats.size

  def to_engine(rules)
    Hjerterfri::Round.from_strings(rules:, deal:, passes:, plays:, pass_direction:)
  end
end
