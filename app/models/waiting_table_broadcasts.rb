# What everyone hears when a bord that has not started changes
# (WaitingTables#change): the lobby its list again when the bord is listed
# or was, the bord's own page its entry (or, once it is gone, that it
# started or closed), and each friend whose puf appeared or ended a
# notification (NotificationsChannel): a puf that ended says how
# (accepted, declined, withdrawn, expired, or gone with its bord). A
# practice bord has no audience but its player, who gets the answer to
# their own request.
module WaitingTableBroadcasts
  module_function

  def changed(before:, after:, registry:)
    table = after || before
    return if table.practice?

    LobbyChannel.broadcast_tables if before&.listed? || after&.listed?
    LobbyChannel.broadcast_waiting_table(table.id, page_entry(table, after, registry))
    tell_nudged(before, after)
  end

  # The bord's page follows it to the stored table once its spil started.
  def page_entry(table, after, registry)
    return after.lobby_entry if after

    stored = registry.started_as(table.id)&.then { |id| Table.find_by(id:) }
    stored ? stored.lobby_entry : table.with(status: "closed").lobby_entry
  end

  def tell_nudged(before, after)
    was = before ? before.pending_nudges.index_by(&:id) : {}
    now = after ? after.pending_nudges.index_by(&:id) : {}
    table = after || before
    (now.keys - was.keys).each { |id| NotificationsChannel.broadcast_nudge(table, now[id]) }
    (was.keys - now.keys).each do |id|
      ended = after&.nudges&.find { |nudge| nudge.id == id } || was[id].with(state: "gone")
      NotificationsChannel.broadcast_nudge_gone(table, ended)
    end
  end
end
