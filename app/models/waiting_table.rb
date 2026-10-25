# A bord before its first spil: listed in the lobby, but not stored in the
# database. Who sits where, the bots, the rules, the type and the game the
# bord plays live here until the vært starts the spil with every seat
# taken; only then do the tables, seats and games rows exist
# (WaitingTable#start, Table.store!). See
# docs/adr/0002-waiting-tables-in-memory.md.
#
# It is the same bord as a stored Table, in its first state, and has the
# same shape: every action at it is a method that takes the user and
# `surroundings:` (Table::Surroundings) and returns a Table::Outcome,
# accepted or refused with a reason (WaitingTable::Actions). The spil's own
# actions do nothing yet; the table chat works as at a stored bord
# (Table::Chatting).
#
# The game is chosen in the lobby when the bord is made and never changes
# (GAMES; only hjerterfri is built). Its Rules (the type, TableRules, and
# the card game's, GameRules) and the password may change until the start.
# The vært (`host_id`) owns the bord.
#
# Puf (ticket 16): the vært nudges friends to the bord. A pending puf holds
# a seat: pending pufs + seated players + bots never exceed four, so
# someone else may not take the last free seats while they are held, and
# the vært may neither nudge nor put a bot there. A puf is accepted (the
# friend is seated), declined, withdrawn by the vært, or expires
# NUDGE_LIFETIME after it was sent; the clock is passed in (`now`). When the
# spil starts or the bord closes, every pending puf is gone with it.
#
# Plain Ruby and immutable: each change (the with_* methods below) returns
# a new WaitingTable, which the actions store in WaitingTables (the
# in-memory registry) under its lock. Changes that can be refused return
# [table, refusal], with the table unchanged on a refusal.
#
# It quacks like a Table where the views and channels need it to: its own
# #seating (occupants and seat_of), #closed?, #current_game, #lobby_entry
# and a route of its own (/borde/:id).
WaitingTable = Data.define(:id, :game, :host_id, :password_digest, :rules, :seats, :nudges, :nudge_count, :status, :created_at)

class WaitingTable
  extend ActiveModel::Naming
  include ActiveModel::Conversion
  include Actions
  include Table::Chatting

  SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT
  # The games a bord can be made for; es-makker is shown as coming soon.
  GAMES = %w[ hjerterfri ].freeze
  NUDGE_LIFETIME = 5 * 60
  Occupant = Table::Seating::Occupant

  # A puf to the friend `user_id`: pending, accepted, declined, withdrawn
  # or expired. `id` counts within its bord.
  Nudge = Data.define(:id, :user_id, :name, :expires_at, :state) do
    def pending? = state == "pending"
    def as_json(*) = { "id" => id, "user_id" => user_id, "name" => name, "state" => state, "expires_at" => expires_at.utc.iso8601 }
  end

  # A new bord with `host` in seat 0 (and three bots at a practice bord),
  # with its Rules.
  def self.build(host:, rules:, game: "hjerterfri", password: nil)
    seats = Array.new(SEAT_COUNT) { |seat| Occupant.new(seat:, user_id: nil, name: nil) }
    seats[0] = Occupant.new(seat: 0, user_id: host.id, name: host.username)
    (1...SEAT_COUNT).each { |seat| seats[seat] = Occupant.new(seat:, user_id: nil, name: "Bot #{seat}", bot_level: Table::Seating::BOT_LEVEL) } if rules.table.practice?
    new(id: new_id, game:, host_id: host.id, password_digest: digest(password), rules:,
        seats: seats.freeze, nudges: [].freeze, nudge_count: 0, status: "waiting", created_at: Time.current)
  end

  # The bord the players who stay after a finished spil wait at for the
  # next one: the stored table's rules, password and vært, and who still
  # sits where (`occupants`).
  def self.after_spil(table, occupants)
    new(id: new_id, game: "hjerterfri", host_id: table.host_id, password_digest: table.password_digest,
        rules: table.rules, seats: occupants.map { |occupant| occupant.with(**Table::Seating::NOT_PRESENT) }.freeze,
        nudges: [].freeze, nudge_count: 0, status: "waiting", created_at: Time.current)
  end

  # Ids are short, start with a letter (never mistaken for a table id) and
  # are hard to guess, so a private bord's link stays its invitation.
  def self.new_id = "b#{SecureRandom.alphanumeric(9).downcase}"

  def self.digest(password)
    return nil if password.blank?

    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    BCrypt::Password.create(password.to_s, cost:).to_s
  end

  def to_param = id
  def persisted? = true

  # The current version of this bord in the registry, or a closed copy of
  # it once it is gone (started or closed).
  def reload(waiting_tables = WaitingTables.default) = waiting_tables.find(id) || with(status: "closed")

  def kind = rules.kind
  def waiting? = status == "waiting"
  def playing? = false
  def closed? = status == "closed"
  def practice? = rules.table.practice?
  def open? = rules.table.open?
  def password? = rules.table.password?
  def private? = rules.table.private?
  def listed? = rules.table.listed?
  def current_game = nil
  # No spil waits for anyone yet (Table#seconds_to_return).
  def seconds_to_return(_user, now:) = nil

  # The bord's own seats stand in for a Table::Seating.
  def seating = self
  def occupants = seats

  def seat_of(player) = Table::Seating.seat_of(player, seats)
  def seated?(user) = !seat_of(user).nil?
  def open_to?(user) = seated?(user)
  def humans = seats.select(&:human?)
  def full? = seats.none?(&:empty?)
  def host = User.find(host_id)
  def host?(user) = host_id == user.id
  def host_name = seats.find { |occupant| occupant.user_id == host_id }&.name

  # How the lobby and the page call it: "Annas bord", "Anders' bord".
  def name
    return "Øvebord" if practice?

    owner = host_name.to_s
    owner.match?(/[sxz]\z/i) ? "#{owner}' bord" : "#{owner}s bord"
  end

  def admits?(password)
    return true unless password?

    BCrypt::Password.new(password_digest) == password.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Who sits where, in the form a spil stores as its start (Game#seats).
  def snapshot = Table::Seating.snapshot_of(seats)

  # --- Sitting, bots and settings ---

  # Why the user may not sit in `seat`, or nil when they may: the password
  # is wrong at a password table, the seat does not exist or is taken, or
  # the free seats left are held by pufs to others (:seat_reserved). Moving
  # to another free seat needs no password. (One bord per user is the
  # action's check: it needs the database.)
  def refusal_to_sit(user, seat, password: nil)
    return :wrong_password unless seated?(user) || nudge_for(user.id) || admits?(password)

    refusal_to_fill(seat) || (:seat_reserved unless seated?(user) || nudge_for(user.id) || free_seats > pending_nudges.size)
  end

  # The user sits in `seat` (or moves there); a puf to them is accepted.
  def with_seated(user, seat)
    stood = seats.map { |occupant| occupant.user_id == user.id ? empty_seat(occupant.seat) : occupant }
    stood[seat] = Occupant.new(seat:, user_id: user.id, name: user.username)
    with(seats: stood.freeze, nudges: answered(user.id, "accepted"))
  end

  # The user has stood up. If they were the vært, the next human in seat
  # order takes over. With no humans left the bord is over: check #humans.
  def without(user_id)
    seat = seats.find { |occupant| occupant.user_id == user_id }&.seat
    return self unless seat

    after = with(seats: replace(seat, empty_seat(seat)))
    return after unless host_id == user_id

    next_host = after.humans.min_by { |human| (human.seat - seat) % SEAT_COUNT }
    next_host ? after.with(host_id: next_host.user_id) : after
  end

  def refusal_to_fill(seat)
    return :no_such_seat unless seat?(seat)

    :seat_taken unless seats.fetch(seat).empty?
  end

  def seat?(seat) = seat.is_a?(Integer) && (0...SEAT_COUNT).cover?(seat)

  # A bot in the empty seat `seat`, unless the free seats are held by pufs.
  def with_bot(seat)
    refusal = refusal_to_fill(seat) || (:seat_reserved unless free_seats > pending_nudges.size)
    return [ self, refusal ] if refusal

    taken = seats.map(&:name)
    name = (1..).lazy.map { |number| "Bot #{number}" }.find { |candidate| taken.exclude?(candidate) }
    [ with(seats: replace(seat, Occupant.new(seat:, user_id: nil, name:, bot_level: Table::Seating::BOT_LEVEL))), nil ]
  end

  # `seat` emptied: a bot taken out or a player kicked.
  def emptied(seat) = with(seats: replace(seat, empty_seat(seat)))

  # New Rules: the card game's, and at a bord that is not a practice bord
  # its type too, with a new password, or the one it has when `password` is
  # blank. A practice bord stays one.
  def with_settings(rules:, password: nil)
    return with(rules: self.rules.with(game: rules.game)) if practice?

    digest = if !rules.table.password? then nil
    elsif password.present? then self.class.digest(password)
    else password_digest
    end
    with(rules:, password_digest: digest)
  end

  # --- Puf ---

  def pending_nudges = nudges.select(&:pending?)

  # The pending puf to the user, or nil.
  def nudge_for(user_id) = pending_nudges.find { |nudge| nudge.user_id == user_id }

  # A puf from the vært to `friend` at `now`. Refused when the friend sits
  # here already, has a pending puf, or no seat is left for them (pending
  # pufs + seated players + bots would exceed four). An earlier, answered
  # puf to the same friend is replaced.
  def with_nudge(friend, now:)
    return [ self, :already_seated ] if seated?(friend)
    return [ self, :already_nudged ] if nudge_for(friend.id)
    return [ self, :nudge_cap ] unless free_seats > pending_nudges.size

    nudge = Nudge.new(id: nudge_count + 1, user_id: friend.id, name: friend.username, expires_at: now + NUDGE_LIFETIME, state: "pending")
    [ with(nudges: [ *nudges.reject { |old| old.user_id == friend.id }, nudge ].freeze, nudge_count: nudge.id), nil ]
  end

  # The vært's pending puf `nudge_id` withdrawn.
  def with_withdrawn(nudge_id)
    nudge = pending_nudges.find { |candidate| candidate.id == nudge_id }
    return [ self, :no_such_nudge ] unless nudge

    [ with(nudges: answered(nudge.user_id, "withdrawn")), nil ]
  end

  # The friend `user` answered their pending puf. Accepting seats them in
  # the first free seat, without the password.
  def with_answer(nudge_id, user, accept:)
    nudge = pending_nudges.find { |candidate| candidate.id == nudge_id && candidate.user_id == user.id }
    return [ self, :no_such_nudge ] unless nudge
    return [ with(nudges: answered(user.id, "declined")), nil ] unless accept

    seat = seats.find(&:empty?)&.seat
    return [ self, :seat_taken ] unless seat

    [ with_seated(user, seat), nil ]
  end

  # Pending pufs whose time is up at `now` expired.
  def with_expired_nudges(now)
    return self if pending_nudges.none? { |nudge| nudge.expires_at <= now }

    with(nudges: nudges.map { |nudge| nudge.pending? && nudge.expires_at <= now ? nudge.with(state: "expired") : nudge }.freeze)
  end

  # --- Showing it ---

  # The same shape as Table#lobby_entry, so the lobby lists both alike.
  # `reserved`: free seats held by pending pufs. Never the password.
  def lobby_entry
    {
      id:, name:, path: "/borde/#{id}", game:, kind:, host: host_name, host_id:, status:, rules: rules.game.to_h,
      seats: seats.map { |occupant| Table::Seating.lobby_seat(occupant) },
      nudges: nudges.map(&:as_json), reserved: pending_nudges.size
    }.as_json
  end

  private

  # The bord as it is now, for the table chat (Table::Chatting).
  def afresh(surroundings) = reload(surroundings.waiting_tables)

  def free_seats = seats.count(&:empty?)

  def empty_seat(seat) = Occupant.new(seat:, user_id: nil, name: nil)

  def replace(seat, occupant) = seats.dup.tap { |copy| copy[seat] = occupant }.freeze

  def answered(user_id, state)
    nudges.map { |nudge| nudge.pending? && nudge.user_id == user_id ? nudge.with(state:) : nudge }.freeze
  end
end
