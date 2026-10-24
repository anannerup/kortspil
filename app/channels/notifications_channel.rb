# Personal notifications for the signed-in user (friend requests, friends
# coming online or going offline, nudges later), and the source of online
# presence. The browser subscribes on every page (app/frontend/notifications).
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

  def subscribed
    stream_for current_user
    current_user.come_online!
  end

  def unsubscribed
    current_user.go_offline!
  end
end
