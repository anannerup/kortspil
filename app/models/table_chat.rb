# The table chat: what the players at each bord have said, the last LIMIT
# messages per bord. It lives in memory in this process only and is lost on
# restart (accepted for v1, see PLAN.md); a bord's log is forgotten when
# the bord closes (Table), and moves with it when it starts (#move).
# Plain Ruby, no ActiveRecord: TableCommands
# decides who may post and read, and tells the seats.
#
# A message is plain text on one line, at most MAX_LENGTH characters, and
# a player may post at most FLOOD_COUNT messages in FLOOD_WINDOW seconds.
# A message that breaks this is refused with a reason (:blank, :too_long,
# :too_fast), not raised. Time comes from the injected clock.
#
# One TableChat is shared by every Action Cable worker thread (DEFAULT), so
# reads and writes hold a lock.
class TableChat
  LIMIT = 50
  MAX_LENGTH = 300
  FLOOD_COUNT = 5
  FLOOD_WINDOW = 10

  # One message: who wrote it (user, seat and name at the time) and when.
  # Ids grow across all bords, so a client can tell new from seen.
  Entry = Data.define(:id, :user_id, :seat, :name, :text, :at) do
    def as_json(*) = { "id" => id, "user_id" => user_id, "seat" => seat, "name" => name, "text" => text, "at" => at.utc.iso8601 }
  end

  # The result of #post: the stored entry, or why the message was refused.
  Posted = Data.define(:entry, :refusal) do
    def refused? = !refusal.nil?
  end

  def initialize(clock: Time)
    @clock = clock
    @lock = Mutex.new
    @logs = {}
    @last_id = 0
  end

  # The process-wide chat that TableCommands uses by default.
  def self.default = DEFAULT

  # Stores what `author` (a Table::Seating::Occupant) said at the bord.
  def post(table_id, author:, text:)
    clean = text.to_s.gsub(/[[:cntrl:]]/, " ").squish
    return Posted.new(entry: nil, refusal: :blank) if clean.empty?
    return Posted.new(entry: nil, refusal: :too_long) if clean.length > MAX_LENGTH

    @lock.synchronize do
      log = @logs[table_id] ||= []
      now = @clock.now
      next Posted.new(entry: nil, refusal: :too_fast) if flooding?(log, author.user_id, now)

      entry = Entry.new(id: @last_id += 1, user_id: author.user_id, seat: author.seat, name: author.name, text: clean, at: now)
      log << entry
      log.shift while log.size > LIMIT
      Posted.new(entry:, refusal: nil)
    end
  end

  # The bord's messages, oldest first.
  def messages(table_id) = @lock.synchronize { (@logs[table_id] || []).dup }

  def forget(table_id) = @lock.synchronize { @logs.delete(table_id) }

  # The bord's log goes along when the bord gets a new id: a waiting bord
  # (WaitingTable) becomes a stored table at the start, and back after a
  # spil.
  def move(from_id, to_id)
    @lock.synchronize do
      log = @logs.delete(from_id)
      @logs[to_id] = log if log
    end
  end

  private

  def flooding?(log, user_id, now)
    log.count { |entry| entry.user_id == user_id && entry.at > now - FLOOD_WINDOW } >= FLOOD_COUNT
  end

  DEFAULT = new
end
