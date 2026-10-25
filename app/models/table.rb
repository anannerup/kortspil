# A bord whose spil has started: the room a spil is played in. A bord
# exists in the database only from its first spil on; before that it is a
# WaitingTable, in memory (docs/adr/0002-waiting-tables-in-memory.md), and
# its "Start spil" (WaitingTable#start, Table.store!) creates the table,
# its seat rows and the spil in one transaction. It hosts games in sequence
# ("Spil igen"); the latest one is the current game. Who sits where is its
# Seating, stored as four seat rows. When a player stands up after a
# finished spil, the bord closes and the others wait for the next spil at
# a new WaitingTable.
#
# Everything that happens at the bord is an action on it, and the bord
# decides what is allowed: each returns an Outcome, accepted with the
# messages for each human seat, or refused with a reason. Callers
# broadcast the messages (TableChannel.deliver) or render the refusal.
# - In the spil (Table::Playing): pass, play, the moon choice, the next
#   runde, "Spil igen". Pass, play and the moon choice are a player's: a
#   human's or a bot's (Table::BotPlayer), which acts for itself through
#   the same actions on its turn.
# - Presence and the tur-ur (Table::Presence): connect, heartbeat,
#   disconnect, the tur-ur's tick.
# - Leaving (Table::Leaving): "Forlad bordet".
# - The table chat (Table::Chatting), before and during a spil.
# What can only be done before the spil (sitting, bots, settings, pufs,
# the start) is the waiting bord's (WaitingTable); a stored bord refuses it
# (:not_waiting). Each action takes `surroundings:` (Table::Surroundings):
# the clock, the shuffler, the bots' lots, the scheduler, the chat and the
# registry of waiting borde, injected so tests are deterministic.
#
# The vært (`host`) owns the bord. Practice tables seat the player and
# three bots. Open tables are listed in the lobby while they play; password
# tables too, with a lock (only the password's digest is stored). Private
# tables are not listed.
#
# The lobby is told after every change to a table or its seats
# (LobbyChannel), so it updates live.
#
# Its `game` is the card game it was made for in the lobby: hjerterfri or
# es-makker ("esmakker"); every spil at it is that game.
#
# Its Rules are the vært's choice before the start: the bord's own
# (TableRules, stored in `kind` and, at es-makker, `runder`) and the card
# game's (GameRules, stored in `rules` as the game's rules hash). They are
# locked: each spil snapshots the game's rules, and they never change once
# the table is stored.
class Table < ApplicationRecord
  include Playing
  include Presence
  include Leaving
  include Chatting

  belongs_to :host, class_name: "User"
  has_many :games, dependent: :destroy
  has_many :seats, dependent: :destroy

  has_secure_password validations: false

  # No enum scopes: one would be named `private`.
  enum :kind, { practice: "practice", open: "open", password: "password", private: "private" }, validate: true, scopes: false
  enum :status, { playing: "playing", closed: "closed" }, validate: true

  validates :game, inclusion: { in: GameRules::GAMES }

  before_validation -> { self.password_digest = nil }, unless: :password?
  validates :password_digest, presence: true, if: :password?
  validate :rules_locked, on: :update

  after_commit :refresh_lobby
  after_commit :forget_chat, if: -> { closed? && saved_change_to_status? }

  # The borde the user has a seat at, closed ones included.
  scope :with_seated, ->(user) { where(id: Seat.occupied_by(user).select(:table_id)) }
  # The borde the lobby lists, oldest first: open and password tables.
  scope :listed, -> { where(kind: TableRules::LISTED_KINDS).not_closed.order(:id) }
  # The borde in use, for the admin page.
  scope :active, -> { not_closed.order(:id) }

  # The waiting bord's spil starts: the bord, its seat rows (every seat
  # taken, heard from `at`) and the spil with its first runde are stored
  # in one transaction. Returns the stored table.
  def self.store!(waiting, at:, shuffler:)
    transaction do
      table = create!(game: waiting.game, host_id: waiting.host_id, password_digest: waiting.password_digest, rules: waiting.rules, status: :playing)
      table.seating.seat_everyone!(waiting.occupants).heard_from_all!(at:)
      Game.start!(table:, rules: table.rules.game, shuffler:)
      table
    end
  end

  def current_game = games.order(:id).last

  def name = practice? ? "Øvebord" : "Bord #{id}"

  def esmakker? = game == "esmakker"

  # The bord's Rules: its own (the type, `kind`, and the number of runder,
  # `runder`) and the card game's (`rules`, read with GameRules).
  def rules = Rules.new(table: TableRules.new(kind:, runder:), game: GameRules.from_stored(super, game:))

  # Takes Rules (both parts), or the card game's alone (GameRules or its
  # stored hash).
  def rules=(rules)
    if rules.is_a?(Rules)
      self.kind = rules.kind
      self.runder = rules.runder
      rules = rules.game
    end
    super(rules.to_h.as_json)
  end

  # Read fresh on every call; keep the result for the length of an action.
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

    game.turn_clock.away(seat, at: now).seconds_left(seat, now)
  end

  # How the lobby shows the table: type, vært, status, rules and who sits
  # where, in the same shape as WaitingTable#lobby_entry. Never the password.
  def lobby_entry
    seats = seating.occupants.map { |occupant| Seating.lobby_seat(occupant) }
    { id:, name:, path: "/tables/#{id}", game:, kind:, host: host.username, host_id:,
      status:, rules: rules.game.to_h, runder:, bots_allowed: GameRules.bots?(game), seats:, nudges: [], reserved: 0 }.as_json
  end

  # Sends the lobby the listed tables again (this one may just have been
  # listed or stopped being listed by closing). Practice tables are never
  # listed.
  def refresh_lobby
    LobbyChannel.broadcast_tables unless practice?
  end

  # --- Before the spil ---

  # What only a bord waiting for its spil can do (WaitingTable): once it is
  # stored, its spil has started, and the bord refuses.
  %i[ sit kick add_bot remove_bot change_settings nudge withdraw_nudge answer_nudge expire_nudges start ].each do |action|
    define_method(action) { |**| Outcome.new(table: self, refusal: :not_waiting) }
  end

  private

  # Yields the current game and the seat of `player` (a User, or a
  # BotPlayer). A player who does not sit at the table, or any player once
  # it is closed, gets no messages.
  def seated(player)
    seat = seating.seat_of(player)
    game = current_game
    return Outcome.new(table: self) if seat.nil? || game.nil? || closed?

    yield game, seat
  end

  def humans(seating) = seating.occupants.select(&:human?)

  def state_messages(game, surroundings)
    humans(game.seating).map { |human| state_message(game, human.seat, human.user_id, surroundings) }
  end

  def state_message(game, seat, user_id, surroundings)
    Message.new(seat:, user_id:, payload: { type: "state", state: game.state_for(seat, now: surroundings.now) }.as_json)
  end

  def closed_message(user_id) = Message.new(seat: nil, user_id:, payload: { "type" => "closed" })

  # The in-memory table chat goes with the bord.
  def forget_chat = TableChat.default.forget(id)

  def rules_locked
    errors.add(:rules, "kan ikke ændres, når spillet er startet") if will_save_change_to_rules? || will_save_change_to_runder? || will_save_change_to_game?
  end
end
