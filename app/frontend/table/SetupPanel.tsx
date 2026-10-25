import { useEffect, useState } from "react"
import type { Friend, LobbySeat, LobbyTable, TableKind } from "~/lobby/messages"
import { TableKindPill } from "~/lobby/TableKindPill"
import { ChatLog, UnreadBadge } from "./Chat"
import type { RuleToggle, Rules, SeatIndex } from "./messages"
import { freeForNudge, friendStatus, isEmpty, seatRoles, setupStatus } from "./setup"
import { RULE_LABELS } from "./texts"
import type { TableChat } from "./useTableChat"

/** What the panel and the seats can do; each resolves to whether the bord took it. */
export interface SetupActions {
  busy: boolean
  sit: (seat: SeatIndex) => Promise<boolean>
  addBot: (seat: SeatIndex) => Promise<boolean>
  removeBot: (seat: SeatIndex) => Promise<boolean>
  kick: (seat: SeatIndex) => Promise<boolean>
  /** The whole settings form, as WaitingTables::SettingsController reads it. */
  saveSettings: (fields: Record<string, string>) => Promise<boolean>
  /** The vært nudges a friend to the bord (puf), or withdraws a pending puf. */
  nudge: (friendId: number) => Promise<boolean>
  withdrawNudge: (nudgeId: number) => Promise<boolean>
  leave: () => void
}

type Tab = "bord" | "chat"

const KINDS: { kind: TableKind; label: string; hint: string }[] = [
  { kind: "open", label: "Åbent bord", hint: "Vises i lobbyen. Alle kan sætte sig." },
  { kind: "password", label: "Med adgangskode", hint: "Vises i lobbyen med en lås. Man skal kende adgangskoden for at sætte sig." },
  { kind: "private", label: "Privat bord", hint: "Vises ikke i lobbyen. Kun dem, der får linket, kan finde bordet." },
]

const INVITE_HINTS: Record<TableKind, string> = {
  open: "Bordet vises i lobbyen. Send linket til dem, du vil spille med.",
  password: "Bordet vises i lobbyen med en lås. Send linket, og fortæl dem adgangskoden.",
  private: "Bordet vises ikke i lobbyen. Kun dem, der får linket, kan finde det.",
}

const TOGGLES = Object.keys(RULE_LABELS) as RuleToggle[]

/** The settings form's fields (GameRules.form_fields, WaitingTables::SettingsController). */
function settingsFields(rules: Rules, kind: LobbyTable["kind"], password = ""): Record<string, string> {
  const fields: Record<string, string> = { "rules[end_score]": String(rules.end_score), kind }
  for (const toggle of TOGGLES) fields[`rules[${toggle}]`] = rules[toggle] ? "1" : "0"
  if (password) fields.password = password
  return fields
}

/**
 * The panel on the right of the bord before its spil, where the spil has
 * its panel too: the bord's settings (rules, type and seats), inviting
 * (the vært's pufs to friends, and the link) and the chat. The vært
 * changes the settings here, and each change is saved at once; everyone
 * else sees them read-only. The game was chosen in the lobby and is not a
 * setting. The seat list is where each bot's level goes (ticket 22).
 */
export function SetupPanel(props: { table: LobbyTable; userId: number; seated: boolean; isHost: boolean; actions: SetupActions; chat: TableChat; friends: Friend[] }) {
  const { table, userId, seated, isHost, actions, chat, friends } = props
  const practice = table.kind === "practice"
  const hasChat = seated && !practice
  const [tab, setTab] = useState<Tab>("bord")
  const { setViewing } = chat
  useEffect(() => setViewing(tab === "chat"), [setViewing, tab])

  return (
    <aside className="table-panel setup-panel" aria-label="Bordet">
      <p className="table-panel-info">
        <a href="/" className="table-lobby-link">
          ‹ Lobby
        </a>
        {practice ? "" : ` · Vært: ${table.host}`}
      </p>
      <h1 className="setup-title">
        {table.name} {!practice && <TableKindPill kind={table.kind} />}
      </h1>

      {hasChat && (
        <nav className="table-tabs setup-tabs" aria-label="Faner">
          {(["bord", "chat"] as const).map((key) => (
            <button key={key} type="button" className={tab === key ? "is-on" : undefined} aria-pressed={tab === key} onClick={() => setTab(key)}>
              <span aria-hidden="true">{key === "bord" ? "⚙" : "✉"}</span>
              {key === "bord" ? "Bordet" : "Chat"}
              {key === "chat" && tab !== "chat" && <UnreadBadge count={chat.unread} />}
            </button>
          ))}
        </nav>
      )}

      {tab === "chat" && hasChat ? (
        <div className="table-panel-body is-chat">
          <ChatLog chat={chat} userId={userId} />
        </div>
      ) : (
        <div className="table-panel-body setup-body">
          <section className="setup-section" aria-labelledby="setup-rules">
            <h2 id="setup-rules">Regler</h2>
            {isHost ? <RulesSettings table={table} actions={actions} /> : <RulesSummary rules={table.rules} />}
          </section>

          {!practice && (
            <section className="setup-section" aria-labelledby="setup-kind">
              <h2 id="setup-kind">Bordtype</h2>
              {isHost ? <KindSettings table={table} actions={actions} /> : <KindSummary kind={table.kind as TableKind} />}
            </section>
          )}

          <section className="setup-section" aria-labelledby="setup-seats">
            <h2 id="setup-seats">Pladser</h2>
            <ol className="setup-seats">
              {table.seats.map((seat) => (
                <SeatRow key={seat.seat} seat={seat} table={table} userId={userId} isHost={isHost && !practice} canSit={!practice && !(table.kind === "password" && !seated)} actions={actions} />
              ))}
            </ol>
            {practice && <p className="setup-hint">Ved et øvebord spiller du mod tre bots. Det tæller ikke i nogen statistik.</p>}
          </section>

          {seated && !practice && (
            <section className="setup-section" aria-labelledby="setup-invite">
              <h2 id="setup-invite">Inviter</h2>
              {isHost && <NudgeFriends table={table} friends={friends} actions={actions} />}
              <p className="setup-hint">{INVITE_HINTS[table.kind as TableKind]}</p>
              <CopyLink link={window.location.origin + table.path} />
            </section>
          )}
        </div>
      )}

      <p className="table-status" aria-live="polite">
        {setupStatus(table, userId)}
      </p>
      <div className="table-panel-buttons">
        {seated ? (
          <button type="button" className="table-btn table-btn-danger" onClick={actions.leave}>
            {practice ? "Luk øvebordet" : "Rejs dig fra bordet"}
          </button>
        ) : (
          <a href="/" className="table-btn setup-lobby-button">
            Tilbage til lobbyen
          </a>
        )}
      </div>
    </aside>
  )
}

/** The vært's rules: the end score (saved when you leave the field) and each house rule (saved at once). */
function RulesSettings({ table, actions }: { table: LobbyTable; actions: SetupActions }) {
  const { rules, kind } = table
  const [endScore, setEndScore] = useState(String(rules.end_score))
  useEffect(() => setEndScore(String(rules.end_score)), [rules.end_score])

  const saveEndScore = () => {
    const value = Number(endScore)
    if (!Number.isInteger(value) || value <= 0) {
      setEndScore(String(rules.end_score))
      return
    }
    if (value !== rules.end_score) void actions.saveSettings(settingsFields({ ...rules, end_score: value }, kind))
  }

  return (
    <ul className="table-panel-rules setup-rules">
      <li className="setup-end-score">
        <label htmlFor="setup-end-score">Spillet slutter ved</label>
        <span>
          <input
            id="setup-end-score"
            type="number"
            min={1}
            step={1}
            inputMode="numeric"
            value={endScore}
            disabled={actions.busy}
            onChange={(event) => setEndScore(event.target.value)}
            onBlur={saveEndScore}
            onKeyDown={(event) => {
              if (event.key === "Enter") event.currentTarget.blur()
            }}
          />{" "}
          point
        </span>
      </li>
      {TOGGLES.map((toggle) => (
        <li key={toggle} className={rules[toggle] ? "is-on" : undefined}>
          <label className="setup-toggle">
            <input
              type="checkbox"
              checked={rules[toggle]}
              disabled={actions.busy}
              onChange={(event) => void actions.saveSettings(settingsFields({ ...rules, [toggle]: event.target.checked }, kind))}
            />
            <span>{RULE_LABELS[toggle]}</span>
          </label>
        </li>
      ))}
    </ul>
  )
}

/** The rules as everyone else sees them, as in the spil's Regler tab. */
function RulesSummary({ rules }: { rules: Rules }) {
  return (
    <ul className="table-panel-rules setup-rules">
      <li className="setup-end-score">Spillet slutter ved {rules.end_score} point</li>
      {TOGGLES.map((toggle) => (
        <li key={toggle} className={rules[toggle] ? "is-on" : undefined}>
          {rules[toggle] ? "✓" : "–"} {RULE_LABELS[toggle]}
        </li>
      ))}
    </ul>
  )
}

/**
 * The vært's table type. Open and private are saved at once; the password
 * type needs a password first (a password table keeps its own when the
 * field is left blank, and can get a new one here).
 */
function KindSettings({ table, actions }: { table: LobbyTable; actions: SetupActions }) {
  const [choice, setChoice] = useState<TableKind>(table.kind as TableKind)
  const [password, setPassword] = useState("")
  useEffect(() => setChoice(table.kind as TableKind), [table.kind])

  const choose = (kind: TableKind) => {
    setChoice(kind)
    if (kind !== "password") void actions.saveSettings(settingsFields(table.rules, kind))
  }
  const savePassword = async () => {
    if (await actions.saveSettings(settingsFields(table.rules, "password", password))) setPassword("")
  }

  return (
    <>
      <ul className="table-panel-rules setup-kinds">
        {KINDS.map((option) => (
          <li key={option.kind} className={choice === option.kind ? "is-on" : undefined}>
            <label className="setup-toggle">
              <input type="radio" name="setup-kind" checked={choice === option.kind} disabled={actions.busy} onChange={() => choose(option.kind)} />
              <span>
                {option.label}
                <small>{option.hint}</small>
              </span>
            </label>
          </li>
        ))}
      </ul>
      {choice === "password" && (
        <form
          className="setup-password-form"
          onSubmit={(event) => {
            event.preventDefault()
            void savePassword()
          }}
        >
          <label htmlFor="setup-table-password">{table.kind === "password" ? "Ny adgangskode" : "Adgangskode"}</label>
          <div>
            <input id="setup-table-password" type="text" autoComplete="off" value={password} onChange={(event) => setPassword(event.target.value)} />
            <button type="submit" className="table-btn table-btn-primary" disabled={password.trim() === "" || actions.busy}>
              Gem
            </button>
          </div>
        </form>
      )}
    </>
  )
}

function KindSummary({ kind }: { kind: TableKind }) {
  const option = KINDS.find((entry) => entry.kind === kind)
  return (
    <p className="setup-hint">
      <strong>{option?.label}</strong> · {option?.hint}
    </p>
  )
}

/**
 * One seat in the list: who sits there and what the vært can do with it.
 * A bot's row has room for its level (ticket 22: Let, Mellem or Svær,
 * chosen per bot here); until then it is empty.
 */
function SeatRow(props: { seat: LobbySeat; table: LobbyTable; userId: number; isHost: boolean; canSit: boolean; actions: SetupActions }) {
  const { seat, table, userId, isHost, canSit, actions } = props
  const roles = seatRoles(seat, table, userId)
  const isMe = seat.user_id === userId
  const seated = table.seats.some((entry) => entry.user_id === userId)

  return (
    <li className={`setup-seat${isEmpty(seat) ? " is-free" : ""}`}>
      <span className="setup-seat-number">{seat.seat + 1}</span>
      <span className="setup-seat-name">
        {seat.name ?? "Ledig"}
        {roles.length > 0 && <small> {roles.join(" · ")}</small>}
      </span>
      {/* Ticket 22: the bot's level goes here. */}
      <span className="setup-seat-level" />
      <span className="setup-seat-actions">
        {isEmpty(seat) && canSit && (
          <button type="button" className="setup-chip setup-chip-primary" disabled={actions.busy} onClick={() => void actions.sit(seat.seat)}>
            {seated ? "Flyt hertil" : "Sæt dig"}
          </button>
        )}
        {isEmpty(seat) && isHost && (
          <button type="button" className="setup-chip" disabled={actions.busy} onClick={() => void actions.addBot(seat.seat)}>
            + Bot
          </button>
        )}
        {isHost && seat.bot && (
          <button type="button" className="setup-chip" disabled={actions.busy} onClick={() => void actions.removeBot(seat.seat)}>
            Fjern bot
          </button>
        )}
        {isHost && !seat.bot && !isEmpty(seat) && !isMe && (
          <button
            type="button"
            className="setup-chip setup-chip-danger"
            disabled={actions.busy}
            onClick={() => {
              if (window.confirm(`Fjern ${seat.name} fra bordet?`)) void actions.kick(seat.seat)
            }}
          >
            Fjern
          </button>
        )}
      </span>
    </li>
  )
}

/**
 * The vært's friends and a "Puf" for each: the friend is told at once,
 * wherever they are on the site, and accepting seats them. A pending puf
 * holds a free seat, so there are never more pufs out than free seats; it
 * can be withdrawn, and expires after about five minutes.
 */
function NudgeFriends({ table, friends, actions }: { table: LobbyTable; friends: Friend[]; actions: SetupActions }) {
  if (friends.length === 0) {
    return (
      <p className="setup-hint">
        Du har ingen venner at puffe endnu. <a href="/friendships">Find venner</a>
      </p>
    )
  }
  const room = freeForNudge(table)

  return (
    <>
      <p className="setup-hint">
        Puf en ven til bordet. {room > 0 ? `Plads til ${room === 1 ? "1 puf" : `${room} puf`} mere.` : "Alle ledige pladser er optaget eller holdt til et puf."}
      </p>
      <ul className="setup-friends">
        {friends.map((friend) => {
          const status = friendStatus(table, friend)
          return (
            <li key={friend.id} className="setup-friend">
              <span className={`setup-friend-dot${friend.online ? " is-online" : ""}`} aria-hidden="true" />
              <span className="setup-friend-name">
                {friend.username}
                <small>{status.label}</small>
              </span>
              {status.pending ? (
                <button type="button" className="setup-chip" disabled={actions.busy} onClick={() => status.pending && void actions.withdrawNudge(status.pending.id)}>
                  Træk tilbage
                </button>
              ) : (
                status.label !== "Sidder ved bordet" && (
                  <button type="button" className="setup-chip setup-chip-primary" disabled={!status.canNudge || actions.busy} onClick={() => void actions.nudge(friend.id)}>
                    Puf
                  </button>
                )
              )}
            </li>
          )
        })}
      </ul>
    </>
  )
}

/** The table's link with a button that copies it. */
function CopyLink({ link }: { link: string }) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard
      ?.writeText(link)
      .then(() => setCopied(true))
      .catch(() => setCopied(false))
  }

  return (
    <div className="setup-link">
      <a href={link}>{link}</a>
      <button type="button" className="setup-chip" onClick={copy}>
        {copied ? "Kopieret" : "Kopiér link"}
      </button>
    </div>
  )
}
