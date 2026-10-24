# A bord: the room a spil is played in. It hosts games in sequence; the
# latest one is the current game. Who sits where is its Seating, stored as
# four seat rows. Practice tables seat the host and three bots and start at
# once, and stay open for further spil until the player leaves. Open tables
# are listed in the lobby: they wait while players sit and stand, and the
# vært starts the spil once every seat is taken. Password and private
# tables come later (ticket 14).
#
# The lobby is told after every change to a listed table or its seats
# (LobbyChannel), so it updates live.
#
# `rules` is the rules config the host chose (Hjerterfri::Rules#to_h). Each
# spil snapshots it when it starts. It is locked once the first runde is
# dealt, that is once the table has a spil.
class Table < ApplicationRecord
  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy
  has_many :seats, dependent: :destroy

  enum :kind, { practice: "practice", open: "open" }, validate: true
  enum :status, { waiting: "waiting", playing: "playing", closed: "closed" }, validate: true

  validate :rules_unchanged_once_dealt, on: :update

  after_commit :refresh_lobby

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }
  # The borde the lobby lists, oldest first.
  scope :listed, -> { open.not_closed.order(:id) }
  # The borde in use, for the admin page.
  scope :active, -> { not_closed.order(:id) }

  def current_game = games.order(:id).last

  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  # Read fresh on every call; keep the result for the length of a command.
  def seating = Seating.new(self)

  def seated?(user) = Seat.occupied_by(user).exists?(table_id: id)

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)

  # The seconds the user has left to come back to the spil in progress
  # here before a bot takes their seat, counting them as frakoblet from
  # `now` if they are not yet (their table page may only just have closed).
  # Nil when no spil waits for them: not seated, a practice table, or no
  # spil in progress. For the lobby banner.
  def seconds_to_return(user, now:)
    seat = seating.seat_of(user)
    game = current_game
    return nil unless open? && playing? && seat && game&.in_progress?

    LiveGame.load(game).turn_clock.away(seat, at: now).seconds_left(seat, now)
  end

  # How the lobby shows the table: vært, status, rules and who sits where.
  def lobby_entry
    seats = seating.occupants.map { |occupant| { seat: occupant.seat, name: occupant.name, user_id: occupant.user_id, bot: occupant.bot? } }
    { id:, host: host.username, host_id:, status:, rules: engine_rules.to_h, seats: }.as_json
  end

  # Sends the lobby the listed tables again when this one is listed (or
  # just stopped being, by closing).
  def refresh_lobby
    LobbyChannel.broadcast_tables if open?
  end

  private

  def rules_unchanged_once_dealt
    errors.add(:rules, "kan ikke ændres, når første runde er givet") if will_save_change_to_rules? && games.exists?
  end
end
