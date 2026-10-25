# A bord whose spil has started: the room a spil is played in. A bord
# exists in the database only from its first spil on; before that it is a
# WaitingTable, in memory (docs/adr/0002-waiting-tables-in-memory.md), and
# TableCommands#start creates the table, its seat rows and the spil in one
# transaction. It hosts games in sequence ("Spil igen"); the latest one is
# the current game. Who sits where is its Seating, stored as four seat
# rows. When a player stands up after a finished spil, the bord closes and
# the others wait for the next spil at a new WaitingTable.
#
# Practice tables seat the player and three bots. Open tables are listed in
# the lobby while they play; password tables too, with a lock (only the
# password's digest is stored). Private tables are not listed.
#
# The lobby is told after every change to a table or its seats
# (LobbyChannel), so it updates live.
#
# `rules` is the rules config the vært chose before the start
# (Hjerterfri::Rules#to_h). It is locked: each spil snapshots it, and it
# never changes once the table is stored.
class Table < ApplicationRecord
  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy
  has_many :seats, dependent: :destroy

  # The types a vært can choose; a practice table is made by "Øvebord".
  # No enum scopes: one would be named `private`.
  CHOOSABLE_KINDS = %w[ open password private ].freeze
  LISTED_KINDS = %w[ open password ].freeze

  has_secure_password validations: false

  enum :kind, { practice: "practice", open: "open", password: "password", private: "private" }, validate: true, scopes: false
  enum :status, { playing: "playing", closed: "closed" }, validate: true

  before_validation -> { self.password_digest = nil }, unless: :password?
  validates :password_digest, presence: true, if: :password?
  validate :rules_locked, on: :update

  after_commit :refresh_lobby
  after_commit :forget_chat, if: -> { closed? && saved_change_to_status? }

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }
  # The borde the lobby lists, oldest first: open and password tables.
  scope :listed, -> { where(kind: LISTED_KINDS).not_closed.order(:id) }
  # The borde in use, for the admin page.
  scope :active, -> { not_closed.order(:id) }

  def current_game = games.order(:id).last

  def name = practice? ? "Øvebord" : "Bord #{id}"

  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  # Read fresh on every call; keep the result for the length of a command.
  def seating = Seating.new(self)

  def seated?(user) = Seat.occupied_by(user).exists?(table_id: id)

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)

  # Whether `password` lets the user sit down: always at a table without
  # a password.
  def admits?(password) = !password? || authenticate_password(password.to_s).present?

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

  # How the lobby shows the table: type, vært, status, rules and who sits
  # where, in the same shape as WaitingTable#lobby_entry. Never the password.
  def lobby_entry
    seats = seating.occupants.map { |occupant| { seat: occupant.seat, name: occupant.name, user_id: occupant.user_id, bot: occupant.bot? } }
    { id:, name:, path: "/tables/#{id}", game: "hjerterfri", kind:, host: host.username, host_id:,
      status:, rules: engine_rules.to_h, seats:, nudges: [], reserved: 0 }.as_json
  end

  # Sends the lobby the listed tables again (this one may just have been
  # listed or stopped being listed by closing). Practice tables are never
  # listed.
  def refresh_lobby
    LobbyChannel.broadcast_tables unless practice?
  end

  private

  # The in-memory table chat goes with the bord.
  def forget_chat = TableChat.default.forget(id)

  def rules_locked
    errors.add(:rules, "kan ikke ændres, når spillet er startet") if will_save_change_to_rules?
  end
end
