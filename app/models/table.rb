# A bord: the room a spil is played in. It hosts games in sequence; the
# latest one is the current game. Practice tables seat the host and three
# bots and start at once, and stay open for further spil until the player
# leaves. Open, password and private tables come later.
class Table < ApplicationRecord
  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy

  enum :kind, { practice: "practice" }, validate: true
  enum :status, { waiting: "waiting", playing: "playing", closed: "closed" }, validate: true

  def current_game = games.order(:id).last

  def seated?(user) = !current_game&.seat_of(user).nil?

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)
end
