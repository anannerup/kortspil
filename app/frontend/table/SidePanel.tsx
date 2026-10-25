import { useEffect, useState, type ReactNode } from "react"
import { Card, parseCardCode } from "~/cards"
import { ChatLog, ChatSheet, UnreadBadge } from "./Chat"
import type { SeatIndex, TableState } from "./messages"
import { ScoreTable } from "./ScoreSheet"
import type { LastTrick } from "./timeline"
import type { Position } from "./Trick"
import { DIRECTION_LABELS, RULE_LABELS, rulesSummary } from "./texts"
import type { TableChat } from "./useTableChat"

type Tab = "spil" | "stilling" | "regler" | "chat"
const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: "spil", label: "Spil", icon: "🂠" },
  { key: "stilling", label: "Stilling", icon: "☰" },
  { key: "regler", label: "Regler", icon: "⚙" },
  { key: "chat", label: "Chat", icon: "✉" },
]

/** When the panel is a bar under the felt (the media query in table.css). */
const NARROW = "(max-width: 820px), (orientation: portrait)"

/**
 * The white panel beside the felt: tabs (the spil, the score sheet, the
 * rules), each seat's points, the last stik, the status line and the big
 * buttons at the bottom. On a narrow or portrait screen it is a bar under
 * the felt with the points, the status and the buttons (CSS).
 */
export function SidePanel(props: {
  state: TableState
  title: string
  connected: boolean
  status: ReactNode
  positionOf: (seat: SeatIndex) => Position
  /** "Næste runde" / "Til bordet" (after the spil), when there is one. */
  primary: { label: string; onClick: () => void } | null
  onShowScore: () => void
  onLeave: () => void
  chat: TableChat
  userId: number
  /** The stik that last left the table (Trick decides when). */
  lastTrick: LastTrick
}) {
  const { state, title, connected, status, positionOf, primary, onShowScore, onLeave, chat, userId, lastTrick } = props
  const { view, seats, score } = state
  const [tab, setTab] = useState<Tab>("spil")
  const [chatSheet, setChatSheet] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const narrow = useMediaQuery(NARROW)
  const finished = state.status === "finished"

  // The sheet is for narrow screens; on a wide one the chat is a tab.
  useEffect(() => {
    if (narrow && tab === "chat") {
      setTab("spil")
      setChatSheet(true)
    } else if (!narrow && chatSheet) {
      setChatSheet(false)
      setTab("chat")
    }
  }, [narrow, chatSheet, tab])
  const { setViewing } = chat
  useEffect(() => setViewing(chatSheet || (!narrow && tab === "chat")), [setViewing, chatSheet, narrow, tab])

  return (
    <aside className="table-panel" aria-label="Spillet">
      <nav className="table-tabs" aria-label="Faner">
        {TABS.map((item) => (
          <button key={item.key} type="button" className={tab === item.key ? "is-on" : undefined} aria-pressed={tab === item.key} onClick={() => setTab(item.key)}>
            <span aria-hidden="true">{item.icon}</span>
            {item.label}
            {item.key === "chat" && tab !== "chat" && <UnreadBadge count={chat.unread} />}
          </button>
        ))}
      </nav>
      <p className="table-panel-info">
        <a href="/" className="table-lobby-link">
          ‹ Lobby
        </a>{" "}
        · {title} · Runde {state.round_number} · bytte {DIRECTION_LABELS[view.pass_direction].toLowerCase()}
        {!connected && <span className="table-offline"> · Forbinder…</span>}
      </p>

      <div className={`table-panel-body${tab === "spil" ? " is-spil" : ""}${tab === "chat" ? " is-chat" : ""}`}>
        {tab === "spil" && (
          <>
            <div className="table-pills">
              {seats.map((seat) => (
                <div key={seat.seat} className={`table-pill${view.to_act === seat.seat ? " is-active" : ""}${score.leaders.includes(seat.seat) ? " is-leader" : ""}`}>
                  <span>{seat.seat === view.seat ? "Dig" : seat.name}</span>
                  <strong>{state.points_taken[seat.seat] ?? 0}</strong>
                  <small>i alt {score.totals[seat.seat] ?? 0}</small>
                </div>
              ))}
            </div>
            <div className="table-lastbox">
              <h3>Sidste stik</h3>
              <div className="table-mini" role="group" aria-label="Sidste stik">
                {lastTrick.plays.map((play) => (
                  <div key={play.card} className={`table-mini-${positionOf(play.seat)}`}>
                    <Card {...parseCardCode(play.card)} size="sm" className={play.seat === lastTrick.winner ? "is-winner" : undefined} />
                  </div>
                ))}
              </div>
            </div>
          </>
        )}
        {tab === "stilling" && (
          <div className="table-panel-score">
            <p>Til {score.end_score} point. Laveste total vinder.</p>
            <ScoreTable seats={seats} score={score} />
          </div>
        )}
        {tab === "chat" && !narrow && <ChatLog chat={chat} userId={userId} />}
        {tab === "regler" && (
          <div className="table-panel-rules">
            <p>Spillet slutter ved {state.rules.end_score} point.</p>
            <ul>
              {(Object.keys(RULE_LABELS) as (keyof typeof RULE_LABELS)[]).map((toggle) => (
                <li key={toggle} className={state.rules[toggle] ? "is-on" : undefined}>
                  {state.rules[toggle] ? "✓" : "–"} {RULE_LABELS[toggle]}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>

      <p className="table-status" aria-live="polite">
        {status}
      </p>
      <div className="table-panel-buttons">
        {primary && (
          <button type="button" className="table-btn table-btn-primary" onClick={primary.onClick}>
            {primary.label}
          </button>
        )}
        <button type="button" className="table-btn table-panel-chat-button" onClick={() => setChatSheet(true)}>
          Chat
          <UnreadBadge count={chat.unread} />
        </button>
        <button type="button" className="table-btn table-panel-score-button" onClick={onShowScore} title={rulesSummary(state.rules)}>
          Stilling
        </button>
        {confirmLeave ? (
          <div className="table-leave-confirm" role="alertdialog" aria-label="Forlad bordet">
            <span>
              {state.table_kind === "practice"
                ? "Forlad bordet? Spillet slutter her."
                : "Forlad bordet? Du taber spillet, og en bot overtager din plads. Du kan ikke vende tilbage til dette spil."}
            </span>
            <button type="button" className="table-btn table-btn-danger" onClick={onLeave}>
              Ja, forlad
            </button>
            <button type="button" className="table-btn" onClick={() => setConfirmLeave(false)}>
              Bliv
            </button>
          </div>
        ) : (
          <button type="button" className="table-btn table-btn-danger" onClick={() => (finished ? onLeave() : setConfirmLeave(true))}>
            Forlad bordet
          </button>
        )}
      </div>
      {chatSheet && <ChatSheet chat={chat} userId={userId} onClose={() => setChatSheet(false)} />}
    </aside>
  )
}

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches)
  useEffect(() => {
    const list = window.matchMedia(query)
    const change = () => setMatches(list.matches)
    change()
    list.addEventListener("change", change)
    return () => list.removeEventListener("change", change)
  }, [query])
  return matches
}
