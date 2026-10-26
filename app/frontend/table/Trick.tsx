import { memo, useEffect, useRef } from "react"
import { useReducedMotion } from "motion/react"
import { CardBack, CardFace } from "~/cards"
import { useFlyIntoTrick, useSweep, type FlightSource } from "./CardAnimations"
import type { SeatIndex, TrickPlay } from "./messages"

export type Position = "south" | "west" | "north" | "east"
export const POSITIONS: Position[] = ["south", "west", "north", "east"]
/** Es-makker: the code of the melder's fordækt card while it lies face down in the stik. */
const FACE_DOWN = "fordaekt"

/**
 * The stik in the middle: four fixed slots, drawing the timeline's frame
 * (timeline.ts decides what lies here and when it sweeps). Cards that
 * appear fly in from their seat; when the frame says so, the stik slides
 * off to its winner (CardAnimations). Cards already on the table at page
 * load do not fly.
 * With reduced motion there is no flight.
 *
 * At es-makker the melder's fordækt card lies face down ("fordaekt") in
 * the stik until it is taken; then the server sends its face and it turns
 * over in place (keyed by its seat, so it does not fly in again).
 */
export const Trick = memo(function Trick(props: {
  plays: TrickPlay[]
  sweepTo: SeatIndex | null
  positionOf: (seat: SeatIndex) => Position
  source: (play: TrickPlay) => FlightSource | null
  seatRect: (seat: SeatIndex) => DOMRect | null
}) {
  const { plays, sweepTo, positionOf, source, seatRect } = props
  const reduced = useReducedMotion() ?? false
  const initialCards = useRef(new Set(plays.map((play) => play.card)))
  useEffect(() => initialCards.current.clear(), [])
  const bySlot = new Map(plays.map((play) => [positionOf(play.seat), play]))

  return (
    <div className="table-trick" role="group" aria-label="Stikket">
      {POSITIONS.map((position) => {
        const play = bySlot.get(position)
        return (
          <div key={position} className={`table-trick-slot table-slot-${position}`}>
            <div className="table-slot-empty" />
            {play && (
              <TrickCard
                key={play.fordaekt ? `fordaekt-${play.seat}` : play.card}
                play={play}
                flyIn={!reduced && !initialCards.current.has(play.card)}
                source={source}
                sweepTo={sweepTo === null ? null : () => seatRect(sweepTo)}
              />
            )}
          </div>
        )
      })}
    </div>
  )
})

/** One card in a slot. Moves with transform only, so the layout never changes (CardAnimations). */
function TrickCard(props: {
  play: TrickPlay
  flyIn: boolean
  source: (play: TrickPlay) => FlightSource | null
  sweepTo: (() => DOMRect | null) | null
}) {
  const { play, flyIn, source, sweepTo } = props
  const ref = useRef<HTMLDivElement>(null)
  useFlyIntoTrick(ref, () => (flyIn ? source(play) : null))
  useSweep(ref, sweepTo)
  const faceDown = play.card === FACE_DOWN
  const wasFaceDown = useRef(faceDown)
  const turned = wasFaceDown.current && !faceDown

  return (
    <div ref={ref} className={`table-trick-card${turned ? " is-turned" : ""}`}>
      {faceDown ? <CardBack className="table-trick-back" /> : <CardFace code={play.card} />}
    </div>
  )
}
