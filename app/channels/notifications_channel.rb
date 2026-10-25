# Personal notifications for the signed-in user (friend requests, friends
# coming online or going offline, pufs to a bord), and the source of online
# presence. The browser subscribes on every page (app/frontend/notifications).
#
# Pufs (ticket 16): a friend nudged to a bord gets { type: "nudge" } with the
# bord, who nudged and where to answer, and { type: "nudge_gone" } when the
# puf ends without their answer (withdrawn, expired, the spil started or
# the bord closed). Pending pufs are sent again on subscribing, so a page
# opened later still shows them (WaitingTableBroadcasts sends the rest).
#
# Presence: subscribing marks the user online by setting users.last_seen_at;
# while subscribed, a heartbeat refreshes it every HEARTBEAT_INTERVAL. A user
# is online while last_seen_at is within User::ONLINE_WINDOW. Unsubscribing
# clears it at once. If the server dies without unsubscribing, the user simply
# expires after ONLINE_WINDOW. With several tabs open, closing one clears
# presence until another tab's next heartbeat.
class NotificationsChannel < ApplicationCable::Channel
  HEARTBEAT_INTERVAL = 20.seconds

  periodically every: HEARTBEAT_INTERVAL do
    current_user.mark_online!
  end

  def self.nudge_message(table, nudge)
    { "type" => "nudge", "nudge_id" => nudge.id, "table_id" => table.id, "table_name" => table.name, "from" => table.host_name,
      "path" => "/borde/#{table.id}/nudges/#{nudge.id}", "expires_at" => nudge.expires_at.utc.iso8601 }
  end

  def self.broadcast_nudge(table, nudge) = broadcast_to(User.find(nudge.user_id), nudge_message(table, nudge))

  def self.broadcast_nudge_gone(table, nudge)
    broadcast_to(User.find(nudge.user_id), { "type" => "nudge_gone", "nudge_id" => nudge.id, "table_id" => table.id, "state" => nudge.state })
  end

  def subscribed
    stream_for current_user
    current_user.come_online!
    now = Time.current
    WaitingTables.default.nudges_for(current_user).each do |table, nudge|
      transmit self.class.nudge_message(table, nudge) if nudge.expires_at > now
    end
  end

  def unsubscribed
    current_user.go_offline!
  end
end
