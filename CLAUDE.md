# Kortspil

Multiplayer card games for members and family at kortspil.andersnannerup.dk.
Hjerterfri first; es-makker whist later. Read `PLAN.md` for scope and
decisions, `GLOSSARY.md` for terms, `docs/rules/` for game rules.

- **Backend:** Rails 8, ActiveRecord, SQLite, Action Cable (Solid Cable).
- **Client:** React + TypeScript + Vite. Renders server state only.
- **Deploy:** Kamal to the same VPS as `../training`.
- **Tests:** Minitest. `bin/rails test`.

The server is the only authority on game rules. The client never decides
legality or computes scores; it shows what the server sends and sends intents.

## Two kinds of code

The app has a CRUD side (accounts, admin, friends, tables, nudges) and a game
side (rules engine, bots, table commands, timers). They follow different
conventions on purpose.

### CRUD side: follow Rails

- Rich models: behaviour lives on the model, queries in scopes. ActiveRecord
  is the data layer; no repository or service layer on top.
- Concerns are fine for sharing model or controller behaviour.
- Callbacks are fine for things that belong to saving that record:
  normalising fields, defaults, derived values, broadcasting or enqueuing
  after the record changes. Side effects outside the database (broadcasts,
  jobs) go in `after_commit`, never `after_save`. Be wary of callbacks that
  quietly cascade into other models.
- Controllers and channels are thin: params in, model call, render/broadcast.

### Game side: plain Ruby, explicit data flow

The game is not CRUD, and here these principles pay off:

- **No Rails in the engine.** The rules engine and bots are plain Ruby with
  no ActiveRecord or IO, tested in isolation.
- **Deterministic.** Same rules config + deal + passes + plays gives the same
  state. Randomness (deals) and time (turn timers) are injected
  (`shuffler:`, `clock:` keyword arguments with defaults).
- **Visible data flow.** Pass data as arguments; return new state or explicit
  results rather than mutating instance variables through no-arg methods.
- **Composition.** Behaviour is built from small objects passed in, not from
  shared base classes. Inheritance only for closed sets (e.g. one class per
  game type behind the same interface).
- Persistence happens at the edge: the table command layer loads from and
  saves to ActiveRecord; the engine never touches it.

## For both

- **Earn abstractions.** Start concrete; extract on the second or third real
  occurrence, or to test logic without IO. Duck typing over abstract base
  classes.
- **One abstraction level per method** — orchestrate or do the work — unless
  the method is small and stable. Don't split ten lines for purity.
- **Exceptions** mean an operation could not complete. Expected outcomes —
  an illegal move, a wrong table password, a full table — return an explicit
  result. Map real failures to responses in one place (`rescue_from`).
- **Method length** ~30 lines; longer is fine if linear and simple.
- **Guard clauses** and early returns over nesting.
- **nil:** return `[]` for collections; never `nil` as a secret error signal.
- **Names** say which domain concept a thing owns, using `GLOSSARY.md` terms:
  `Hjerterfri::Round`, `TableChannel` — not `GameHelper`, `Manager`.

## TypeScript

- `strict` mode. Server message types are defined once and shared.
- Components render the state the server sends; no game rules client-side.

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
