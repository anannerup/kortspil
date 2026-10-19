class Table
  # Who sits where at a bord, before and during a spil: the one place that
  # knows which seats hold humans, which hold bots and which are empty,
  # where a user sits, and how a bot takes over a seat. Backed by the
  # `seats` rows (see docs/adr/0001-seats-table.md); a game's `seats`
  # column is only the snapshot taken when that spil started.
  #
  # Rules for sitting and standing before the start, one bord per user,
  # vært handover and the puf cap (tickets 12, 13, 16) belong here.
  #
  # A Seating is read once: methods that change seats return a new one.
  class Seating
    SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT

    # A seat and who is in it: a user (user_id and their name), a bot
    # (name only) or nobody.
    Occupant = Data.define(:seat, :user_id, :name) do
      def human? = !user_id.nil?
      def bot? = user_id.nil? && !name.nil?
      def empty? = user_id.nil? && name.nil?
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
    def snapshot
      raise ArgumentError, "a spil starts with every seat taken" if occupants.any?(&:empty?)

      occupants.map do |occupant|
        occupant.human? ? { "kind" => "human", "user_id" => occupant.user_id } : { "kind" => "bot", "name" => occupant.name }
      end
    end

    # A practice bord: the user in seat 0 and bots in the other three.
    def seat_practice!(user)
      Seat.transaction do
        Seat.create!(table: @table, position: 0, user:)
        (1...SEAT_COUNT).each { |seat| Seat.create!(table: @table, position: seat, bot_name: bot_name(seat)) }
      end
      Seating.new(@table)
    end

    # A bot takes over the human's seat in the spil `game` from step
    # `at_play` (LiveGame#version) on; the change is appended to the
    # spil's seat_log so replays know who acted when.
    def take_over!(seat, game:, at_play:)
      from = occupants.fetch(seat)
      raise ArgumentError, "seat #{seat} has no human to take over from" unless from.human?

      to = free_bot_name
      Seat.transaction do
        Seat.find_by!(table_id: @table.id, position: seat).update!(user: nil, bot_name: to)
        game.update!(seat_log: [ *game.seat_log, { "seat" => seat, "from" => from.user_id, "to" => to, "at_play" => at_play } ])
      end
      Seating.new(@table)
    end

    # Whether the user has forladt the spil: a bot took over their seat,
    # or they left the spil and lost it. They may not return to it.
    def forladt?(user, game)
      game.forfeited_by_id == user.id || game.seat_log.any? { |entry| entry["from"] == user.id }
    end

    private

    def occupant(seat, row)
      return Occupant.new(seat:, user_id: nil, name: nil) if row.nil?

      Occupant.new(seat:, user_id: row.user_id, name: row.user ? row.user.username : row.bot_name)
    end

    def bot_name(number) = "Bot #{number}"

    def free_bot_name
      taken = occupants.map(&:name)
      (1..).lazy.map { |number| bot_name(number) }.find { |name| taken.exclude?(name) }
    end
  end
end
