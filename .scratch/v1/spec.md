Status: ready-for-agent

# Spec: Kortspil v1 — hjerterfri online for members and family

## Problem Statement

Anders and his family and friends want to play card games together when they
are not in the same room. Existing online card sites are full of strangers,
ads and rule variants nobody in the family plays. There is no place where an
approved group of people can sit down at a table, invite each other, play
hjerterfri by their own house rules, chat while playing, and keep a record of
every game for later.

## Solution

A private web site at kortspil.andersnannerup.dk. Anyone can create an
account, but only accounts Anders approves can play. Approved users see a
lobby of tables, can start their own **bord**, choose whether it is open,
password-protected or private, set the rules, fill empty seats with bots, and
**nudge** friends to join. The **spil** is played live in the browser with
animated cards; the server enforces every rule. Each **bord** has its own
chat. If a player disappears or stalls, the others wait up to 60 seconds,
let a bot take over, or end the **spil**. Every **runde** is stored so games
can be replayed and analysed later.

Desktop first, usable on a phone browser. Danish UI.

## User Stories

### Account and access

1. As a visitor, I want to create an account with a username, email and password, so that I can ask to join.
2. As a visitor, I want my username to be unique and visible to other players, so that people know who they are playing with.
3. As a new user, I want to log in right after signing up, so that I know my account works.
4. As a new user who is not yet approved, I want to see a clear "Afventer godkendelse" page instead of the lobby, so that I know why I cannot play yet.
5. As a new user, I want my access to open as soon as I am approved, without re-registering, so that getting started is painless.
6. As a user, I want to log in with my username or my email plus password, so that I don't have to remember which one I used.
7. As a user, I want to stay logged in on my device, so that I don't type my password every time.
8. As a user, I want to log out, so that I can use a shared family computer safely.
9. As a user, I want to change my own password, so that I can keep my account secure.
10. As a blocked user, I want to be refused login with a plain message, so that the situation is unambiguous.

### Admin

11. As the admin, I want to see a list of users awaiting approval, so that I can let the right people in.
12. As the admin, I want to approve or reject a pending user, so that only people I know can play.
13. As the admin, I want to see all users with their status, so that I have an overview of who has access.
14. As the admin, I want to set a new password for a user, so that I can help someone who forgot theirs (there is no email reset in v1).
15. As the admin, I want to block a user, so that I can remove access without deleting their game history.
16. As the admin, I want to see the tables that are currently active, so that I can see what is going on.
17. As the admin, I want admin rights to be granted only from the production console, so that there is no way to escalate through the UI.
18. As a non-admin, I want admin pages to be inaccessible to me, so that the admin area stays private.

### Friends

19. As a player, I want to search for other approved users by username, so that I can find people I know.
20. As a player, I want to send a friend request, so that we can nudge each other to tables.
21. As a player, I want to accept or decline incoming friend requests, so that my friends list contains only people I choose.
22. As a player, I want to see my friends and whether they are online, so that I know whom it makes sense to nudge.
23. As a player, I want to remove a friend, so that I can tidy my list.
24. As a player, I want to see my pending outgoing requests, so that I know who hasn't answered.

### Lobby and tables

25. As a player, I want a lobby listing open and password-protected tables with their seats, host and status, so that I can find a game to join.
26. As a player, I want private tables to be hidden from the lobby, so that a family game isn't interrupted by others.
27. As a player, I want the lobby to update live as tables open, fill and close, so that I don't need to refresh.
28. As a host, I want to create a **bord** and choose its type (open, password, private), so that I control who can join.
29. As a host, I want to set a password on a password table, so that only people I tell can sit down.
30. As a player, I want to join an open table by clicking a free seat, so that joining is one action.
31. As a player, I want to enter the password to join a password table and get a clear message if it is wrong, so that I know what happened.
32. As a player, I want every table to have its own URL, so that a host can send the link to someone directly.
33. As a player opening a private table's link, I want to be able to take a free seat, so that the link works as an invitation.
34. As a player, I want to choose which seat I sit in, so that I can sit across from my partner-in-banter.
35. As a player, I want to leave a table before the **spil** starts, so that I can change my mind.
36. As a player, I want to sit at only one table at a time, so that I don't hold up two games.
37. As a host, I want to kick a player before the **spil** starts, so that I can fix a mistaken join.
38. As a host, I want to put a bot in an empty seat and remove it again before start, so that we can play with fewer than four humans.
39. As a player, I want to start a practice table with three bots, so that I can play alone.
40. As a host, I want to start the **spil** only when all four seats are filled, so that the game is always complete.
41. As a player, I want the host role to pass to the next player if the host leaves, so that the table doesn't get stuck.
42. As a player, I want an empty table (no humans left) to close automatically, so that the lobby doesn't fill with dead tables.

### Nudges

43. As a host, I want to nudge friends to my table, so that they get a direct invitation.
44. As a nudged friend, I want to see the invitation immediately wherever I am on the site, with the host's name and table, so that I can react quickly.
45. As a nudged friend, I want to accept and be seated in one action, so that joining is effortless.
46. As a nudged friend, I want to decline, so that the host knows I'm not coming.
47. As a host, I want to see each nudge's state (pending, accepted, declined, expired), so that I know whom I'm waiting for.
48. As a host, I want to be stopped from nudging more people than there are free seats (pending nudges + seated players + bots ≤ 4), so that I never over-invite.
49. As a host, I want a declined or expired nudge to free its slot for a new nudge, so that I can invite someone else.
50. As a nudged friend, I want a nudge to expire after about five minutes or when the **spil** starts, so that stale invitations disappear.
51. As a host, I want to withdraw a pending nudge, so that I can change my mind.

### Rules configuration

52. As a host, I want a "Standard hjerterfri" preset matching the rules in our rules document, so that the default is what we expect.
53. As a host, I want to change the end score (default 100), so that we can play shorter or longer games.
54. As a host, I want to toggle "spar dame bryder hjerter" (the queen of spades breaks hearts), so that we can play that house rule.
55. As a host, I want to toggle "ruder knægt giver minus 10", so that we can play our house rule.
55a. As a host, I want to toggle shooter's choice, so that a moon shooter may take −26 instead of giving 26 to everyone else.
56. As a player, I want to see the table's rules before I sit down, so that I know what I'm agreeing to.
57. As a player, I want the rules locked once the first **runde** is dealt, so that nothing changes mid-game.

### Playing hjerterfri

58. As a player, I want to see my 13 cards sorted by suit and rank, so that I can plan.
59. As a player, I want to never receive other players' cards from the server, so that nobody can cheat by inspecting the browser.
60. As a player, I want to see each opponent's name, seat, card count and score, so that I can follow the game.
61. As a player, I want to choose three cards to pass in the right direction for this **runde** (left, right, across, none), so that the passing pattern is followed.
62. As a player, I want to see clearly which direction we are passing this **runde**, so that I choose my cards well.
63. As a player, I want passing to be simultaneous and hidden until everyone has chosen, so that the cards I receive can't influence what I pass.
64. As a player, I want to see the three cards I received highlighted, so that I know what came in.
65. As a player, I want the holder of 2♣ to be required to lead it, so that the opening is correct.
66. As a player, I want only my legal cards to be playable and the rest dimmed, so that I can't make an illegal move.
67. As a player, I want to be unable to discard hearts or Q♠ on the first **stik** unless I have nothing else, so that the first-trick rule is enforced.
68. As a player, I want to be unable to lead hearts until hearts are broken, unless I have only hearts, so that the breaking rule is enforced.
69. As a player, I want to see whose turn it is, so that I know when to act.
70. As a player, I want cards to animate from hand to table and from table to the winner, so that the game feels like a card game.
71. As a player, I want to see the cards in the current **stik** and who played each, so that I can follow the play.
72. As a player, I want to see the last completed **stik**, so that I can check what just happened.
73. As a player, I want points for each **runde** counted automatically (1 per heart, 13 for Q♠, −10 for J♦ when enabled), so that scoring is correct.
74. As a player, I want shooting the moon handled automatically (the shooter gets 0 and everyone else 26, or with shooter's choice, the shooter may take −26 instead), so that the special case is correct.
75. As a player, I want a score sheet showing every **runde** and running totals, so that I can see the game's history.
76. As a player, I want the **spil** to end when someone reaches the end score and the lowest score to be declared the winner, so that the result is clear.
77. As a player, I want ties for the lowest score to be shown as shared wins, so that nobody is arbitrarily ranked.
78. As a player, I want to choose "Spil igen" at the end so that the same table starts a new **spil**, so that we can keep playing.
79. As a player, I want to refresh the page or switch device mid-game and land back in my seat with the full state, so that a hiccup doesn't cost me the game.
80. As a player, I want an ongoing **spil** to survive a server deploy or restart, so that Anders can deploy without ruining games.

### Bots

81. As a player, I want bots to always make legal moves, so that games with bots never break.
82. As a player, I want bots to play a simple sensible strategy (pass high cards and Q♠, follow low, dump Q♠ and hearts when void), so that games against them are not trivial.
83. As a player, I want bots to act after a short delay, so that I can follow their moves.
84. As a player, I want bots clearly labelled, so that I know who is human.

### Absence, timeouts and leaving

> Revised 2026-10-20 after a grilling: there is no vote. See ticket 19 and GLOSSARY.md (Forlade, Frakoblet, Vinder, Afbrudt).

85. As an active player, I want a warning if I haven't moved within 30 seconds, so that I'm reminded before I'm counted as gone.
86. As a player, I want to be able to leave a **spil** with "Forlad bordet" (confirmed), knowing I lose it and a bot takes my seat at once, so that I can always get out.
87. As a player whose tab closed or network dropped, I want 60 seconds to come back and keep my seat, so that an accident doesn't cost me the game.
88. As a frakoblet player, I want an impossible-to-miss banner at the top of the lobby with a countdown and "Tilbage til bordet", so that I find my way back in time.
89. As a waiting player, I want to see "Venter på Anders… 0:42" with a countdown, so that I understand the pause.
90. As a waiting player, I want a bot to take over automatically after 60 seconds, so that the game is never stuck.
91. As a player, I want someone who left (actively or by not returning) to lose regardless of points, and the win to go to the human with the lowest total, so that rage-quitting never costs the rest of us a win.
92. As a player, I want a bot never to be able to win, and a tie with a bot to count as my win, so that results reflect humans.
93. As the last human at a **bord**, I want to keep playing against the bots and win only by beating them; if I leave too, the **spil** is stored as afbrudt.

### Chat

94. As a player at a table, I want to send chat messages to everyone at that table, so that we can talk while playing.
95. As a player, I want to see recent table messages when I join or reconnect, so that I have context (as long as the server hasn't restarted).
96. As a player, I want to see who wrote each message and when, so that the conversation is clear.

### History

97. As a player, I want every finished or abandoned **spil** stored with its players, rules, every deal, pass and play, and final scores, so that games can be replayed and analysed later.
98. As a player, I want seat changes during a **spil** (bot takeover, reclaim) recorded, so that a future replay shows who actually played each card.

### Deployment

99. As Anders, I want to deploy with Kamal to the same server as the training app, so that I use one familiar routine.
100. As Anders, I want the app reachable over HTTPS at kortspil.andersnannerup.dk with working WebSockets, so that live play works.

## Implementation Decisions

### Architecture

- **One Rails 8 app** in one container: ActiveRecord on SQLite, Action Cable on Solid Cable for live updates, and a React + TypeScript client built with Vite and served by Rails.
- **Server-rendered pages** for signup, login, the approval page and the admin area. **React** for the lobby, table, game and chat.
- **The server is the only authority.** The client renders the state it receives and sends intents. There are no game rules in TypeScript.

### Modules

- **Hjerterfri rules engine** (plain Ruby, no Rails). It is a deep module with a small interface:
  - Built from a rules config, the seat order, the **runde** number, the deal, the passes made so far and the plays made so far.
  - `apply(seat, intent)` accepts a pass (three cards) or a play (one card). It returns either the new state or a rejection with a reason. A rejected intent is an expected outcome, not an exception.
  - `view_for(seat)` returns everything that seat may know: its own hand, received cards, the pass direction, the current **stik** and the last one, who is to act, the legal moves, card counts per opponent, hearts-broken status, and **runde** points when it is complete.
  - It exposes the phase (passing / playing / complete), and the **runde** result including the shooting-the-moon adjustment.
  - Deals come from an injected shuffler/seed so they are deterministic in tests.
  - A game-level object adds up **runde** results, applies the end score, determines the winner(s) and gives the pass direction for the next **runde**.
- **Rules config:**
  - end score (default 100)
  - Q♠ breaks hearts (default off)
  - J♦ scores −10 (default off). Never for a moon shooter (Anders, 2026-10-25).
  - Shooter's choice (default off): the moon shooter chooses 26 to everyone else or −26 to themselves. Off, everyone else gets 26.
  - The "Standard hjerterfri" preset follows `docs/rules` §3 (Part 3). The Q♠ toggle comes from §3.9. The J♦ toggle is the house rule Anders's table actually plays. The source lists the ten of diamonds instead, which this table has never played.
  - v1 is four players only.
- **Bot player:** given a seat's view, it chooses an intent. It only ever chooses from the legal moves it is given. Strategy is simple and rule-based.
- **Table** (the use-case boundary for everything multiplayer). It is an object that takes commands and returns the per-recipient messages to broadcast. Commands are: create, sit, leave, kick, add/remove bot, set rules, start, nudge, withdraw nudge, answer nudge, pass, play, chat, heartbeat, connect/disconnect, and a clock tick. Time comes from an injected clock, so timers are deterministic.
  - Bots act through the same commands, scheduled by the table after a short delay.
  - The turn timer (warning at 30 s, forladt at 60 s), heartbeats and disconnect handling are driven by the clock tick.
  - It enforces the nudge cap, host handover, auto-close of tables with no humans, one-table-per-player, and the rules lock at the first deal.
- **Channels** (Action Cable): one for the lobby and personal notifications (nudges, friend requests), and one per table. They are thin. They authenticate from the session cookie, turn incoming messages into table commands, and broadcast the results. Each seat gets its own stream, so hidden information never goes to the wrong client.
- **Accounts:** built from the Rails 8 authentication generator. They add a unique username, login by username or email, an approval state (pending / approved / rejected / blocked) and an admin flag. Admin is set only from the console. There are no password-reset emails.
- **Friendships:** mutual, made by a request and an accept. Users can remove a friend.

### Persistence

- **users:** username (unique), email (unique), password digest, approval state, admin flag.
- **friendships:** requester, addressee, state.
- **tables:** host, type, password digest (password tables only), rules config, status. Stored only when the first spil starts; before that the bord lives in memory (`docs/adr/0002-waiting-tables-in-memory.md`).
- **seats:** four rows per bord (position, user or bot name, or empty): who sits there now, before and during a spil. See `docs/adr/0001-seats-table.md`.
- **games:**
  - table, rules config snapshot, status (in progress / finished / abandoned), and final scores
  - the players per seat at the start (a snapshot; never changed)
  - `seat_log`: JSON of seat changes, each entry `{seat, from, to, at_play}`
- **rounds**, one row per **runde** (agreed with Anders, instead of one row per card):
  - `number`, `pass_direction`
  - `deal`: 52 card codes, 13 per seat in seat order
  - `passes`: 12 card codes, 3 per seat in seat order
  - `plays`: card codes in played order, with each new play appended to the string
  - Who played each card is not stored. It can be derived: the holder of 2♣ after the pass leads, and each **stik** winner leads the next.
  - There are no timestamps per card.
- **Card codes** are rank + suit, e.g. `2C`, `TD`, `QS`, `AH`.
- **Live state** for a game in progress is rebuilt from the game and round rows, so it survives deploys. Each command persists before it broadcasts.
- **Nudges** are kept with state and expiry on the bord before its spil, in memory (revised 2026-10-25, `docs/adr/0002-waiting-tables-in-memory.md`).
- **Chat** is kept in memory per table and holds the last ~50 messages. It is lost on restart. This is accepted for v1.
- **Concurrency:** commands for a single table are serialized so two plays can't race. With SQLite and one app process, a per-table lock is enough.

### Client

- **Framework:** React + TypeScript (strict). The message types for every server message are defined in one place.
- **Cards:** DOM cards with the card style taken from Anders's "Hjerterfri" design system (https://claude.ai/artifact/3jSKXTctgM3g9yLPKpyaWe), animated with Motion. Moving to canvas stays possible later.
  - **Taken from the design system:** `Card` and `CardBack`, the suit icons (inline SVG paths using `currentColor`, never emoji), the card tokens (`card-face`, `card-edge`, `card-ink`, `suit-red`, `card-back`, `card-back-line`, `radius-card`/`radius-sm`, `shadow-card`/`shadow-lift`, the three card sizes with height = width × 1.43, the hand overlap), and Fraunces for card indices.
  - **Not taken:** the table, panel, seats, colours outside the cards, and layout. These are not designed yet. Keep that UI plain and neutral so it is easy to restyle later.
- **Input:** click to select cards for passing and click to play. Nothing is drag-only, so touch works.
- **Language:** all UI text is in Danish.

### Deployment

- Kamal, on the same VPS and shared kamal-proxy as the training app. It uses its own service name, image (`anders/kortspil` in the Forgejo registry on repos.andersnannerup.dk) and storage volume, builds for amd64, and runs SSL via Let's Encrypt.
- Cloudflare is set to DNS-only for the A record (Anders sets this up).
- No GitHub: code and images are on Forgejo, and Kamal deploys from Anders' machine.

### Build order

Each slice is deployed when it is done:
1. Accounts, approval, admin.
2. Rules engine and a practice table against three bots, with animations.
3. Lobby and tables with several humans.
4. Friends and nudges.
5. Chat.
6. Timer, keep-alive, leaving and disconnects.

## Testing Decisions

- **Good tests** drive a module only through its public interface and assert on observable results: the rejection reasons, the views, the broadcast messages, the stored rows. They don't assert on private methods, instance variables or the order of internal calls. Randomness and time are injected, so tests are deterministic.
- **Seam 1, the rules engine.** It gets the most thorough coverage:
  - the 2♣ opening
  - following suit
  - the first-**stik** restriction, including the "nothing else" exception
  - hearts breaking, the only-hearts exception, and the Q♠-breaks-hearts toggle
  - pass directions over **runder** 1–5 and simultaneous passing
  - **stik** winners
  - scoring, including J♦ and shooting the moon
  - the end score, and ties for the lowest score
  - the hidden information in `view_for`
  - rebuilding state from stored strings, so that a replay equals live play

  Bot tests run here too: a bot never makes an illegal move over many seeded deals.
- **Seam 2, the table command interface.** This covers multiplayer flows with a fake clock:
  - joining by type and password
  - the nudge cap, expiry and freed slots
  - kicking, host handover and auto-close
  - start conditions and the rules lock
  - per-seat message privacy
  - warning, heartbeat loss, the 60-s window, active and passive leaving, the winner rule, and the last human leaving
  - bot takeover and reclaim, including the `seat_log`
  - abandoned games
  - a **spil** surviving a simulated restart, by rebuilding the table from the database

  Action Cable channels get a single thin smoke test each.
- **Request tests** (existing Rails seam): signup, login by username or email, the pending-approval gate, a blocked user being refused, admin approve/reject/reset/block, and non-admins being denied.
- **No React tests in v1.** TypeScript strict mode is the safety net. The client holds no rules.
- **Prior art:** none in this repo yet. Use standard Minitest with Rails fixtures, as in the sibling training app.

## Out of Scope

- A replay viewer and statistics pages (the data is stored from slice 2).
- Email delivery: password reset by email and signup notifications.
- External login providers.
- A mobile app shell (Capacitor, biometrics/PIN). The web UI must still work with touch.
- Es-makker whist and any other game.
- Hjerterfri for 3 or 5+ players.
- Spectators.
- Lobby-wide chat and private messages.
- Persisting chat.
- Configurable turn timers.
- Smarter bots.

## Further Notes

- **Where the rules come from.** They come from `docs/rules` §3, which is sourced from madskristensen.dk. Two decisions are inferred rather than taken from the source: ties for the lowest score count as a shared win, and 4 players only. The house rules in §3.9 are flagged in the source doc as common but not universal.
- **J♦ and shooting the moon.** "Shooting the moon" is still judged on the 26 penalty points (all hearts + Q♠). Whoever took J♦ gets −10 on top, and that includes the shooter. This is inferred, not taken from a source.
- **How hearts break.** In the source, hearts are broken when a player discards a heart because they can't follow suit. With "Q♠ breaks hearts" on, discarding Q♠ does the same. Whether leading Q♠ counts as breaking is not covered by the source. The proposal is that it does, when the toggle is on.
- **Terms.** Bord, spil, runde, stik, vært, puf, forlade, frakoblet, vinder and afbrudt are defined in `GLOSSARY.md`. "Puf" is a proposed Danish UI word for nudge and has not been confirmed.
- **Testing seams.** The seams (rules engine, table command interface, request tests) were proposed and not objected to before this spec was written.
- **Starting point.** The repo holds an unmodified Rails 8.1 skeleton without Hotwire or importmap, and nothing has been committed yet.
