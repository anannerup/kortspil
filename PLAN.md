# Kortspil — plan

A multiplayer card-game site for members and family, deployed at
**kortspil.andersnannerup.dk**. First game: **hjerterfri**. Es-makker whist
comes later as game no. 2 (rules in `docs/rules/`). Terms: see `GLOSSARY.md`.

Decided in a grilling session on 2026-10-18.

## Stack

- **Backend:** Rails 8, ActiveRecord, SQLite, Action Cable (Solid Cable).
- **Client:** React + TypeScript + Vite (via `vite_rails`), served from the
  same container. All rendering and animation of the game lives here.
- **Cards:** DOM cards + Motion (framer-motion), card style from the "Hjerterfri"
  design system artifact. The rest of the UI is not designed yet; keep it plain.
  Canvas/PixiJS stays an option if this turns out too limiting.
- **Rules engine:** plain Ruby classes (no ActiveRecord). The server is the
  only authority: each player receives only their own hand plus the list of
  legal moves; the client sends intents ("play 7H") and never computes rules.

## Deploy

No GitHub. Code and images live on the Forgejo at **repos.andersnannerup.dk**
(the home server). Deploys run with Kamal from Anders' machine; there is no CI
deploy.

- Kamal, same OVH VPS (141.95.53.184), shared kamal-proxy with Let's Encrypt.
- `service: kortspil`, image `anders/kortspil` in the Forgejo container
  registry, volume `kortspil_storage:/rails/storage`, `builder.arch: amd64`,
  `ssh.user: ubuntu`.
- `KAMAL_REGISTRY_PASSWORD`: a Forgejo token with `write:package`, exported in
  the shell before `bin/kamal deploy`.
- DNS: Cloudflare, **DNS-only** (grey cloud) A record
  `kortspil → 141.95.53.184` — set by Anders.

## Users and admin

- Open signup with username + email + password.
- New users can log in but see only "Afventer godkendelse" until approved.
- Admin = a flag set from the prod Rails console. Admin page: pending users
  (approve/reject), all users (reset password, block), active tables.
- No email delivery in v1.
- Friends are mutual (request → accept).

## Tables (bord)

- Types: **open** (listed in lobby), **password** (listed, lock icon),
  **private** (unlisted; join via nudge or table link). No spectators.
- **Host** = creator. Sets rules config (starting from the "Standard
  hjerterfri" preset), table type and bot seats; starts the game; can kick
  before start. Rules lock when the first round is dealt. If the host leaves,
  host passes to the next player.
- **Nudges:** host can nudge friends; they accept/decline. Pending nudges +
  seated players + bots ≤ 4. A nudge expires after ~5 min or when the game
  starts.
- **Bots:** simple rule-based, allowed in any seat, incl. 1 human + 3 bots
  (practice table). Bots can never be vinder.
- "Spil igen": a new game at the same table with the same players.

## Absence and leaving

Settled in a grilling on 2026-10-20. There is no vote. See ticket 19 and GLOSSARY.md.

- **Keep-alive.** A client heartbeat means a lost connection is noticed within seconds.
- **Frakoblet.** The player has 60 seconds from losing the connection to come back. After that, a bot takes over and the player has forladt.
- **Inactive on your turn.** You get a warning at 30 s. At 60 s you have forladt.
- **"Forlad bordet"** (confirmed) means you have forladt at once, and a bot takes over immediately.
- **Forladt = loss**, whatever the points, and you can't rejoin that spil.
- **Vinder** is the human with the lowest total, and a tie with a bot is still a win. If a bot is alone on the lowest total, there is no vinder.
- **The last human** keeps playing against the bots. If they leave too, the spil is afbrudt.
- **Øvespil** never count in statistics.

## Persistence

- `games`: table, rules config, status, scores, `seat_log` (JSON:
  `[{seat, from, to, at_play}]`) so replays stay correct across seat changes.
- `rounds`: **one row per round** — `game_id`, `number`, `pass_direction`,
  `deal` (52 cards, 13 per seat in seat order), `passes` (12 cards, 3 per seat
  in seat order), `plays` (cards in played order, appended per move).
  Who played each card is implicit: 2C-holder after the pass leads, trick
  winner leads next. No per-card timestamps.
- The engine rebuilds live state from these rows, so games survive deploys.
- **Chat is in memory only** for now (lost on restart). Persist later.

## Build order (each slice deployed when done)

1. Skeleton live: signup, login, approval, admin page.
2. Hjerterfri rules engine in Ruby with tests + practice table vs 3 bots,
   with animations.
3. Lobby and tables (open/password/private), multiple humans over Action Cable.
4. Friends + nudges with accept/decline.
5. Table chat.
6. Turn timer, keep-alive, leaving and disconnects.

v1 = slices 1–6.

## Out of v1

Replay viewer (data is stored from slice 2), statistics, email delivery,
mobile app shell (Capacitor + biometric/PIN — address when we get there),
es-makker whist.
