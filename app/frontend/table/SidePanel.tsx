import { useState, type ReactNode } from "react"
import { Card, parseCardCode } from "~/cards"
import type { SeatIndex, TableState } from "./messages"
import { ScoreTable } from "./ScoreSheet"
import type { Position } from "./Trick"
import { DIRECTION_LABELS, RULE_LABELS, rulesSummary } from "./texts"

type Tab = "spil" | "stilling" | "regler"
const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: "spil", label: "Spil", icon: "🂠" },
  { key: "stilling", label: "Stilling", icon: "☰" },
  { key: "regler", label: "Regler", icon: "⚙" },
]

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
  /** "Næste runde" / "Spil igen", when there is one. */
  primary: { label: string; onClick: () => void } | null
  onShowScore: () => void
  onLeave: () => void
}) {
  const { state, title, connected, status, positionOf, primary, onShowScore, onLeave } = props
  const { view, seats, score } = state
  const [tab, setTab] = useState<Tab>("spil")
  const [confirmLeave, setConfirmLeave] = useState(false)
  const finished = state.status === "finished"

  return (
    <aside className="table-panel" aria-label="Spillet">
      <nav className="table-tabs" aria-label="Faner">
        {TABS.map((item) => (
          <button key={item.key} type="button" className={tab === item.key ? "is-on" : undefined} aria-pressed={tab === item.key} onClick={() => setTab(item.key)}>
            <span aria-hidden="true">{item.icon}</span>
            {item.label}
          </button>
        ))}
      </nav>
      <p className="table-panel-info">
        <a href="/" className="table-lobby-link">
          ‹ Lobby
        </a>{" "}
        · {title} · Runde {state.round_number} · bytning {DIRECTION_LABELS[view.pass_direction].toLowerCase()}
        {!connected && <span className="table-offline"> · Forbinder…</span>}
      </p>

      <div className={`table-panel-body${tab === "spil" ? " is-spil" : ""}`}>
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
                {view.last_trick.map((play) => (
                  <div key={play.card} className={`table-mini-${positionOf(play.seat)}`}>
                    <Card {...parseCardCode(play.card)} size="sm" className={play.seat === view.last_trick_winner ? "is-winner" : undefined} />
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
        <button type="button" className="table-btn table-panel-score-button" onClick={onShowScore} title={rulesSummary(state.rules)}>
          Stilling
        </button>
        {confirmLeave ? (
          <div className="table-leave-confirm" role="alertdialog" aria-label="Forlad bordet">
            <span>Forlad bordet? Du taber spillet.</span>
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
    </aside>
  )
}
