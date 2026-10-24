# 17: Table chat

**What to build:** Players at a table chat with each other. The last 50 messages are kept in memory and shown on joining or reconnecting. They are lost on server restart (accepted for v1).

**Blocked by:** 12 (Lobby and open tables)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] Messages show author and time
- [x] Each table keeps an in-memory buffer of 50 messages that is replayed on subscribe
- [x] Only seated players can post
- [x] Messages are length-limited and rendered as plain text (no HTML)
- [x] A table-seam test covers post and replay

## Comments

- 2026-10-25: Done on branch t17-chat.
  - **Server.** `TableChat` (`app/models/table_chat.rb`, plain Ruby, injected clock) keeps the last 50 messages per bord in memory, behind a mutex, in one process-wide instance (`TableChat.default`). `TableCommands#chat` and `#chat_history` are the table-seam commands: only humans seated at a bord that is not closed may post or read, and a message goes to each seated human's own stream, like every other table message. `TableChannel` gets a `chat` action and sends `chat_history` on subscribe (before the state, so existing `transmissions.last` tests are unchanged). Message types live in `app/frontend/table/messages.ts` (`chat_history`, `chat_message`, `chat_rejected`).
  - **Limits, decided here.** Text is cleaned to one line (control characters to spaces, whitespace squished), at most 300 characters (`TableChat::MAX_LENGTH`, sent to the client with the history). Flood guard: at most 5 messages in 10 seconds per player per bord. Blank, too long and too fast are refused with a reason to the author only (`chat_rejected`), never raised. The client keeps the draft when a message is refused.
  - **Plain text.** The server stores the text as typed (no escaping); React renders it as text. A test checks that `<script>` comes through verbatim.
  - **Before the start too.** Chat works in the waiting room for the seated: `WaitingRoom` subscribes to `TableChannel` only for the chat (an open table's channel already accepted the seated before the start). The log carries over into the spil. Someone who stands up stops getting new messages; someone who sits down gets the history.
  - **Forgetting.** A bord's log is dropped when the bord closes (`Table` `after_commit`), so the in-memory store does not grow with old tables. Lost on restart, as the ticket says.
  - **UI.** A fourth panel tab "Chat" with an unread badge (messages from others that came while the chat was not on screen; the first history on opening counts as read). On narrow/portrait screens a "Chat" button with the badge sits in the bar under the felt and opens the chat as a bottom sheet (Luk / Esc / tap outside). Switching between wide and narrow moves an open chat between tab and sheet. Messages show the author ("Dig" for your own, on the right in green) and the time (da-DK, HH.MM). New messages show for 5 seconds as a speech bubble at the author's name tag on the felt, including your own.
  - Bots don't chat. No chat for practice-table spectators (there are none in v1).
  - Verified with headless Chromium, two and two players: wide iPad landscape, iPad portrait, phone, the flood refusal, the waiting room, and replay after reload.

