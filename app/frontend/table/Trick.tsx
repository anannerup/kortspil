import { memo, useEffect, useLayoutEffect, useRef } from "react"
import { animate, useReducedMotion } from "motion/react"
import { Card, parseCardCode } from "~/cards"
import type { FlightSource } from "./flight"
import type { SeatIndex, TrickPlay } from "./messages"
import { FLY_MS, SWEEP_MS } from "./timeline"

export type Position = "south" | "west" | "north" | "east"
export const POSITIONS: Position[] = ["south", "west", "north", "east"]

/**
 * The stik in the middle: four fixed slots, drawing the timeline's frame
 * (timeline.ts decides what lies here and when it sweeps). Cards that
 * appear fly in from their seat; when the frame says so, the stik slides
 * off to its winner. Cards already on the table at page load do not fly.
 * With reduced motion there is no flight.
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
                key={play.card}
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

const center = (rect: DOMRect) => ({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 })

/** One card in a slot. Moves with transform only, so the layout never changes. */
function TrickCard(props: {
  play: TrickPlay
  flyIn: boolean
  source: (play: TrickPlay) => FlightSource | null
  sweepTo: (() => DOMRect | null) | null
}) {
  const { play, flyIn, source, sweepTo } = props
  const ref = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    const element = ref.current
    const from = flyIn ? source(play) : null
    if (!element || !from) return
    element.style.transform = "none"
    const here = center(element.getBoundingClientRect())
    const there = center(from.rect)
    const controls = animate(
      element,
      { x: [there.x - here.x, 0], y: [there.y - here.y, 0], scale: [from.scale ?? from.rect.width / (element.getBoundingClientRect().width || 1), 1] },
      { duration: FLY_MS / 1000, ease: [0.2, 0.8, 0.25, 1] },
    )
    return () => controls.stop()
  }, []) // On mount only: a card flies in once.

  const sweeping = sweepTo !== null
  useEffect(() => {
    const element = ref.current
    const target = sweepTo?.()
    if (!element || !target) return
    element.style.transform = "none"
    const here = center(element.getBoundingClientRect())
    const there = center(target)
    const controls = animate(
      element,
      { x: there.x - here.x, y: there.y - here.y, scale: 0.35, opacity: 0 },
      { duration: SWEEP_MS / 1000, ease: [0.5, 0, 0.75, 0] },
    )
    return () => controls.stop()
  }, [sweeping]) // Once, when the sweep starts.

  return (
    <div ref={ref} className="table-trick-card">
      <Card {...parseCardCode(play.card)} />
    </div>
  )
}
