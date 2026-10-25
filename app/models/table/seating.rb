class Table
  # Who sits where at a stored bord, during and after its spil: the one place that
  # knows which seats hold humans, which hold bots and which are empty,
  # where a user sits, and how a bot takes over a seat. Backed by the
  # `seats` rows (see docs/adr/0001-seats-table.md); a game's `seats`
  # column is only the snapshot taken when that spil started.
  #
  # Seat rows exist only once a spil has started: before that the bord is a
  # WaitingTable, in memory, where sitting, standing, bots and pufs live
  # (docs/adr/0002-waiting-tables-in-memory.md). #seat_everyone! copies its
  # seats here when the spil starts. Vært handover when a bot takes over,
  # and each human seat's presence during a spil (tickets 18 and 19) live
  # here: when it was last heard from, when it (re)connected, since when it
  # is frakoblet, and when it was last warned on its turn. TurnClock decides
  # from these; the presence writes skip callbacks, as the lobby does not
  # show them.
  #
  # A Seating is read once: methods that change seats return a new one.
  class Seating
    SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT
    NOT_PRESENT = { heartbeat_at: nil, connected_at: nil, disconnected_at: nil, warned_at: nil }.freeze

    # A seat and who is in it: a user (user_id and their name), a bot
    # (name only) or nobody, and for a user their presence.
    Occupant = Data.define(:seat, :user_id, :name, :heartbeat_at, :connected_at, :disconnected_at, :warned_at) do
      def initialize(seat:, user_id:, name:, heartbeat_at: nil, connected_at: nil, disconnected_at: nil, warned_at: nil) = super
      def human? = !user_id.nil?
      def bot? = user_id.nil? && !name.nil?
      def empty? = user_id.nil? && name.nil?
      def frakoblet? = !disconnected_at.nil?
    end

    def initialize(table)
      @table = table
      rows = Seat.where(table_id: table.id).includes(:user).index_by(&:position)
      @occupants = (0...SEAT_COUNT).map { |seat| occupant(seat, rows[seat]) }.freeze
    end

    # The four seats in seat order; seats without a row are empty.
    attr_reader :occupants

    # The seat the user sits in, or nil.
    def seat_of(user) = occupants.find { |occupant| occupant.user_id == user.id }&.seat

    # Who sits where now, in the form a spil stores as its start
    # (Game#seats). Every seat must be taken.
    def snapshot = self.class.snapshot_of(occupants)

    def self.snapshot_of(occupants)
      raise ArgumentError, "a spil starts with every seat taken" if occupants.any?(&:empty?)

      occupants.map do |occupant|
        occupant.human? ? { "kind" => "human", "user_id" => occupant.user_id } : { "kind" => "bot", "name" => occupant.name }
      end
    end

    # The spil starts: the waiting bord's seats (`occupants`, every one
    # taken) become this bord's seat rows.
    def seat_everyone!(occupants)
      raise ArgumentError, "a spil starts with every seat taken" if occupants.any?(&:empty?)

      Seat.transaction do
        occupants.each { |occupant| Seat.create!(table: @table, position: occupant.seat, user_id: occupant.user_id, bot_name: occupant.human? ? nil : occupant.name) }
      end
      Seating.new(@table)
    end

    # When the user `user_id`, who has just left `from_seat`, was the vært,
    # the next human in seat order after that seat becomes vært. Call it on
    # the seating read after they left. With no humans left nothing changes.
    def pass_host_on!(user_id:, from_seat:)
      next_host = occupants.select(&:human?).min_by { |human| (human.seat - from_seat) % SEAT_COUNT }
      @table.update!(host_id: next_host.user_id) if next_host && @table.host_id == user_id
    end

    # A bot takes over the human's seat in the spil `game` from step
    # `at_play` (Game#version) on; the change is appended to the
    # spil's seat_log so replays know who acted when. The seat keeps its
    # running totals (they belong to the seat). A vært who leaves this way
    # hands the vært role on (#pass_host_on!).
    def take_over!(seat, game:, at_play:)
      from = occupants.fetch(seat)
      raise ArgumentError, "seat #{seat} has no human to take over from" unless from.human?

      to = free_bot_name
      Seat.transaction do
        Seat.find_by!(table_id: @table.id, position: seat).update!(user: nil, bot_name: to, **NOT_PRESENT)
        game.update!(seat_log: [ *game.seat_log, { "seat" => seat, "from" => from.user_id, "to" => to, "at_play" => at_play } ])
        Seating.new(@table).tap { |after| after.pass_host_on!(user_id: from.user_id, from_seat: seat) }
      end
    end

    # --- Presence (TurnClock reads it) ---

    # Every human seat counts as heard from at `at`, e.g. when a spil
    # starts, so a player who never opens the table is noticed.
    def heard_from_all!(at:) = presence!(occupants.select(&:human?).map(&:seat), heartbeat_at: at)

    def heartbeat!(seat, at:) = presence!([ seat ], heartbeat_at: at)

    # The seat came back after being frakoblet: heard from, no longer
    # frakoblet, and its wait on its turn starts again (TurnClock).
    def connected!(seat, at:) = presence!([ seat ], heartbeat_at: at, connected_at: at, disconnected_at: nil)

    # The seat is frakoblet from `at` on, unless it already was.
    def disconnected!(seat, at:)
      return self if occupants.fetch(seat).frakoblet?

      presence!([ seat ], disconnected_at: at)
    end

    def warned!(seat, at:) = presence!([ seat ], warned_at: at)

    # Whether the user has forladt the spil: a bot took over their seat,
    # or they left the spil and lost it. They may not return to it.
    def forladt?(user, game)
      game.forfeited_by_id == user.id || game.seat_log.any? { |entry| entry["from"] == user.id }
    end

    private

    def occupant(seat, row)
      return Occupant.new(seat:, user_id: nil, name: nil) if row.nil?
      return Occupant.new(seat:, user_id: nil, name: row.bot_name) unless row.user

      Occupant.new(seat:, user_id: row.user_id, name: row.user.username, **row.slice(*NOT_PRESENT.keys).symbolize_keys)
    end

    def presence!(seats, **columns)
      Seat.where(table_id: @table.id, position: seats).where.not(user_id: nil).update_all(columns)
      Seating.new(@table)
    end

    def free_bot_name
      taken = occupants.map(&:name)
      (1..).lazy.map { |number| "Bot #{number}" }.find { |name| taken.exclude?(name) }
    end
  end
end
