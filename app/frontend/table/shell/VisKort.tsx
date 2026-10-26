import { memo, useEffect, useState } from "react"
import { CardFace, cardLabel, type CardCode } from "~/cards"
import type { SeatIndex, VisKort } from "../messages"
import type { Position } from "../Trick"
import { logThoughts, type LoggedThought } from "./thoughts.ts"

/**
 * A hand laid open at another seat's edge of the felt, in place of its
 * card backs: its cards face up, overlapped so each card's corner shows;
 * played cards fly from here as from a stack. The same at every game: a
 * bot's hand under "Vis kort", and at es-makker the bordlægger's.
 */
export const OpenHand = memo(function OpenHand(props: { anchor: (element: HTMLElement | null) => void; position: Exclude<Position, "south">; cards: CardCode[]; label: string }) {
  const { anchor, position, cards, label } = props
  return (
    <div ref={anchor} className={`table-stack table-open-hand table-open-hand-${position}`} role="img" aria-label={`${label} ${cards.map(cardLabel).join(", ")}`}>
      {cards.map((code) => (
        <CardFace key={code} code={code} size="sm" />
      ))}
    </div>
  )
})

/** The bots' thoughts this runde, one per decision, newest first (logThoughts), from the states as they are shown. */
export function useThoughtLog<T>(visKort: VisKort<T> | null | undefined, roundNumber: number): LoggedThought<T>[] {
  const [log, setLog] = useState<LoggedThought<T>[]>([])
  useEffect(() => setLog((current) => logThoughts(current, visKort, roundNumber)), [visKort, roundNumber])
  return log
}

/**
 * "Vis kort" in the panel's Spil tab, for an admin alone with bots: the
 * switch, and while it is on the bots' thoughts, one line per decision,
 * worded by the game (`lineOf`).
 */
export function VisKortBox<T>(props: {
  visKort: VisKort<T>
  log: LoggedThought<T>[]
  nameOf: (seat: SeatIndex) => string
  lineOf: (thought: T, nameOf: (seat: SeatIndex) => string) => string
  onSwitch: (on: boolean) => void
}) {
  const { visKort, log, nameOf, lineOf, onSwitch } = props
  return (
    <section className="table-vis-kort" aria-label="Vis kort">
      <label className="table-vis-kort-switch">
        <input type="checkbox" checked={visKort.on} onChange={(event) => onSwitch(event.target.checked)} />
        Vis kort <small>bottenes kort og hvad de tænker</small>
      </label>
      {visKort.on && (
        <ol className="table-vis-kort-log">
          {log.length === 0 && <li className="is-empty">Ingen beslutninger endnu i denne runde.</li>}
          {log.map((entry) => (
            <li key={`${entry.seat}:${entry.thought.version}`}>
              <strong>{nameOf(entry.seat)}:</strong> {lineOf(entry.thought, nameOf)}
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}
