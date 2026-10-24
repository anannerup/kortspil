# A bord: the room a spil is played in. It hosts games in sequence; the
# latest one is the current game. Who sits where is its Seating, stored as
# four seat rows. Practice tables seat the host and three bots and start at
# once, and stay open for further spil until the player leaves. Open,
# password and private tables come later.
#
# `rules` is the rules config the host chose (Hjerterfri::Rules#to_h). Each
# spil snapshots it when it starts. It is locked once the first runde is
# dealt, that is once the table has a spil.
class Table < ApplicationRecord
  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy
  has_many :seats, dependent: :destroy

  enum :kind, { practice: "practice" }, validate: true
  enum :status, { waiting: "waiting", playing: "playing", closed: "closed" }, validate: true

  validate :rules_unchanged_once_dealt, on: :update

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }

  def current_game = games.order(:id).last

  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  # Read fresh on every call; keep the result for the length of a command.
  def seating = Seating.new(self)

  def seated?(user) = Seat.occupied_by(user).exists?(table_id: id)

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)

  private

  def rules_unchanged_once_dealt
    errors.add(:rules, "kan ikke ændres, når første runde er givet") if will_save_change_to_rules? && games.exists?
  end
end
