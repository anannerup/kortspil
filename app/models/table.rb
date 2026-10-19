# A bord: the room a spil is played in. It hosts games in sequence; the
# latest one is the current game. Who sits where is its Seating, stored as
# four seat rows. Practice tables seat the host and three bots and start at
# once, and stay open for further spil until the player leaves. Open,
# password and private tables come later.
class Table < ApplicationRecord
  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy
  has_many :seats, dependent: :destroy

  enum :kind, { practice: "practice" }, validate: true
  enum :status, { waiting: "waiting", playing: "playing", closed: "closed" }, validate: true

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }

  def current_game = games.order(:id).last

  # Read fresh on every call; keep the result for the length of a command.
  def seating = Seating.new(self)

  def seated?(user) = Seat.occupied_by(user).exists?(table_id: id)

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)
end
