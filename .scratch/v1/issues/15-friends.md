# 15: Friends

**What to build:** Players search for other approved users, send friend requests, accept or decline them, remove friends and see which friends are online.

**Blocked by:** 03 (Signup, login and approval gate)

**Status:** in-progress

Spec: `.scratch/v1/spec.md`

- [x] Search approved users by username
- [x] Friendships are mutual: a request, then accept or decline
- [ ] The friends list shows online status, which is live through the notification channel
  - Done: presence comes from `NotificationsChannel` (subscribe/heartbeat/unsubscribe set `users.last_seen_at`; online = seen within `User::ONLINE_WINDOW`). Open: the page shows status as of page load; no client listener subscribes yet, so the channel is not opened from the browser and nothing updates live. Comes with the layout-wide listener in 16 (nudges).
- [x] Outgoing pending requests are visible. Friends can be removed.
- [x] Incoming requests show as a notification
  - A count badge on "Venner" in the top bar, and a `friend_request` broadcast on `NotificationsChannel`. The live pop-up listener comes with 16.
- [x] Tests cover the request lifecycle

## Comments

- Merged to main, not deployed yet. Remaining: a live online status needs a browser subscription to NotificationsChannel. That is folded into ticket 16 (nudges), which adds the layout-wide listener.
