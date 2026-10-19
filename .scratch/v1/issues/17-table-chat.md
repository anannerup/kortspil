# 17: Table chat

**What to build:** Players at a table chat with each other. The last 50 messages are kept in memory and shown on joining or reconnecting. They are lost on server restart (accepted for v1).

**Blocked by:** 12 (Lobby and open tables)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Messages show author and time
- [ ] Each table keeps an in-memory buffer of 50 messages that is replayed on subscribe
- [ ] Only seated players can post
- [ ] Messages are length-limited and rendered as plain text (no HTML)
- [ ] A table-seam test covers post and replay
