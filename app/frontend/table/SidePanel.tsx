import type { ReactNode } from "react"
import { Card, parseCardCode } from "~/cards"
import type { HjerterfriTableState, SeatIndex } from "./messages"
import { ScoreTable } from "./ScoreSheet"
import { TablePanel } from "./shell"
import type { LastTrick } from "./timeline"
import type { Position } from "./Trick"
import { DIRECTION_LABELS, RULE_LABELS, rulesSummary } from "./texts"
import type { TableChat } from "./useTableChat"

/**
 * Hjerterfri's panel in the shared frame (TablePanel): each seat's points
 * and the last stik under Spil, the score sheet under Stilling, the house
 * rules under Regler, and "Næste runde" / "Til bordet" as the primary
 * button.
 */
export function SidePanel(props: {
  state: HjerterfriTableState
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
  /** "Vis kort" (VisKortBox), for an admin alone with bots. */
  visKort: ReactNode
}) {
  const { state, title, connected, status, positionOf, primary, onShowScore, onLeave, chat, userId, lastTrick, visKort } = props
  const { view, seats, score } = state

  return (
    <TablePanel
      info={`${title} · Runde ${state.round_number} · bytte ${DIRECTION_LABELS[view.pass_direction].toLowerCase()}`}
      connected={connected}
      chat={chat}
      userId={userId}
      spil={
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
      }
      visKort={visKort}
      stilling={
        <div className="table-panel-score">
          <p>Til {score.end_score} point. Laveste total vinder.</p>
          <ScoreTable seats={seats} score={score} />
        </div>
      }
      regler={
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
      }
      regelbogPath="/regelbog#hjerterfri"
      status={status}
      primary={primary}
      onShowScore={onShowScore}
      scoreTitle={rulesSummary(state.rules)}
      finished={state.status === "finished"}
      practice={state.table_kind === "practice"}
      onLeave={onLeave}
    />
  )
}
