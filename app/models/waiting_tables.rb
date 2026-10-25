# Where the borde that have not started live: in this process's memory,
# like the table chat (TableChat). Nothing is written to the database until
# a spil starts (TableCommands#start). See
# docs/adr/0002-waiting-tables-in-memory.md for why, and for the limits: a
# restart or deploy drops every bord that has not started (and its pufs),
# and the app must run as one web process, as it already must for the
# table chat. Jobs run in Solid Queue's own processes and never touch a
# waiting bord.
#
# One registry (DEFAULT) is shared by every Puma and Action Cable thread.
# #change runs a change to one bord under a reentrant lock (a Monitor: a
# change may ask "where does this user sit?", which reads the registry
# again), so two players cannot take the same seat, and tells the listener
# inside the lock, so broadcasts go out in the order the changes were made.
#
# A bord that started is remembered as the stored table it became, so an
# old link to it leads to the spil (#started_as).
class WaitingTables
  def initialize(listener: WaitingTableBroadcasts)
    @listener = listener
    @monitor = Monitor.new
    @tables = {}
    @started = {}
  end

  # The process-wide registry.
  def self.default = DEFAULT

  def find(id) = synchronize { @tables[id.to_s] }

  def all = synchronize { @tables.values }

  # The listed borde (open and password), oldest first.
  def listed = all.select(&:listed?)

  # The bord the user sits at, or nil.
  def seated(user) = all.find { |table| table.seated?(user) }

  # The pending pufs to the user, with their borde: [[table, nudge], ...].
  def nudges_for(user)
    all.filter_map { |table| table.nudge_for(user.id)&.then { |nudge| [ table, nudge ] } }
  end

  # The id of the stored table the bord `id` became when its spil started.
  def started_as(id) = synchronize { @started[id.to_s] }

  def add(table) = change(table.id) { [ table, table ] }

  # Yields the bord `id` as it is now (nil when there is none) under the
  # lock. The block returns [the bord after, a result]: the bord after is
  # stored, or, when nil, the bord is gone (closed or started). Returns the
  # result.
  def change(id)
    synchronize do
      before = @tables[id.to_s]
      after, result = yield(before)
      after.nil? ? @tables.delete(id.to_s) : @tables[id.to_s] = after
      @listener.changed(before:, after:, registry: self) unless before.equal?(after)
      result
    end
  end

  # Records that the bord `id` became the stored table `table_id`.
  def started!(id, table_id) = synchronize { @started[id.to_s] = table_id }

  # For tests.
  def clear = synchronize { @tables.clear && @started.clear }

  private

  def synchronize(&) = @monitor.synchronize(&)

  DEFAULT = new
end
