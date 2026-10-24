# A bord: the room a spil is played in. It hosts games in sequence; the
# latest one is the current game. Who sits where is its Seating, stored as
# four seat rows. Practice tables seat the host and three bots and start at
# once, and stay open for further spil until the player leaves. Open tables
# are listed in the lobby: they wait while players sit and stand, and the
# vært starts the spil once every seat is taken. Password tables are listed
# too, with a lock, and need the password to sit down; only its digest is
# stored. Private tables are not listed: their link is the invitation.
#
# The lobby is told after every change to a table or its seats
# (LobbyChannel), so it updates live, and so does the table's own waiting
# room.
#
# `rules` is the rules config the host chose (Hjerterfri::Rules#to_h). Each
# spil snapshots it when it starts. It may change only while the table
# waits: it is locked once the first runde is dealt, until the table waits
# for players again after a spil.
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
  enum :status, { waiting: "waiting", playing: "playing", closed: "closed" }, validate: true

  before_validation -> { self.password_digest = nil }, unless: :password?
  validates :password_digest, presence: true, if: :password?
  validate :rules_unchanged_once_dealt, on: :update

  after_commit :refresh_lobby
  after_commit :forget_chat, if: -> { closed? && saved_change_to_status? }

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }
  # The borde the lobby lists, oldest first: open and password tables.
  scope :listed, -> { where(kind: LISTED_KINDS).not_closed.order(:id) }
  # The borde in use, for the admin page.
  scope :active, -> { not_closed.order(:id) }

  def current_game = games.order(:id).last

  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  # Read fresh on every call; keep the result for the length of a command.
  def seating = Seating.new(self)

  def seated?(user) = Seat.occupied_by(user).exists?(table_id: id)

  # A seated user may open the table until it closes.
  def open_to?(user) = !closed? && seated?(user)

  # Whether `password` lets the user sit down: always at a table without
  # a password.
  def admits?(password) = !password? || authenticate_password(password.to_s).present?

  # How the lobby and the waiting room show the table: type, vært, status,
  # rules and who sits where. Never the password.
  def lobby_entry
    seats = seating.occupants.map { |occupant| { seat: occupant.seat, name: occupant.name, user_id: occupant.user_id, bot: occupant.bot? } }
    { id:, kind:, host: host.username, host_id:, status:, rules: engine_rules.to_h, seats: }.as_json
  end

  # Sends the lobby the listed tables again (this one may just have been
  # listed, changed, or stopped being listed by closing or turning private)
  # and the table's own waiting room its entry. Practice tables have
  # neither.
  def refresh_lobby
    return if practice?

    LobbyChannel.broadcast_tables
    LobbyChannel.broadcast_table(self)
  end

  private

  # The in-memory table chat goes with the bord.
  def forget_chat = TableChat.default.forget(id)

  def rules_unchanged_once_dealt
    errors.add(:rules, "kan ikke ændres, når første runde er givet") if will_save_change_to_rules? && !waiting?
  end
end
