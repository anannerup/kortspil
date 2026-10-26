# One runde as stored. Hjerterfri: the deal, the passes and the plays as
# space-separated card codes (see the spec's Persistence section), and the
# moon shooter's choice under shooter's choice. Es-makker: the deal (55
# codes: the hands, then the kitty), the kortgiver's seat and the action
# log. Which columns a runde fills, how it is dealt and how the engine's
# runde is rebuilt from it are its spil's card game's (Game#card_game).
class Round < ApplicationRecord
  belongs_to :game

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :deal, presence: true
  validate :dealt_for_its_game

  private

  def dealt_for_its_game
    game.card_game.round_errors(self).each { |attribute, error| errors.add(attribute, error) }
  end
end
