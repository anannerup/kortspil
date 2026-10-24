import { useEffect, useLayoutEffect, useRef, useState } from "react"
import { animate, useReducedMotion } from "motion/react"
import { Card, parseCardCode } from "~/cards"
import type { SeatIndex, SeatView, TrickPlay } from "./messages"

export type Position = "south" | "west" | "north" | "east"
export const POSITIONS: Position[] = ["south", "west", "north", "east"]

/** Where a card flies in from: a screen rect and the scale it starts at there. */
export interface FlightSource {
  rect: DOMRect
  scale: number
}

// Timings (ms), after the bridge app on iPad: a card takes its time to
// land; a completed stik rests a moment, then slides off to its winner.
const FLY_MS = 440
const PAUSE_MS = 950
const SWEEP_MS = 480

interface Sweep {
  key: string
  plays: TrickPlay[]
  winner: SeatIndex
  stage: "resting" | "leaving"
}

const trickKey = (plays: TrickPlay[]) => plays.map((play) => play.card).join(",")

/**
 * The stik in the middle: four fixed slots. Animation is presentational
 * only. What it shows is always derived from the latest view:
 *
 * - normally the view's current stik;
 * - right after a stik completes (the server has already cleared it and
 *   filled last_trick), the completed stik, which rests and then sweeps to
 *   last_trick_winner. Plays of the next stik that arrive meanwhile wait
 *   for the sweep (it is cut short when they do), then fly in.
 *
 * A newer completed stik replaces a running sweep; a runde without a last
 * stik clears it. With reduced motion there is no sweep and no flight.
 */
export function Trick(props: {
  view: SeatView
  positionOf: (seat: SeatIndex) => Position
  source: (play: TrickPlay) => FlightSource | null
  seatRect: (seat: SeatIndex) => DOMRect | null
}) {
  const { view, positionOf, source, seatRect } = props
  const reduced = useReducedMotion() ?? false
  const lastKey = trickKey(view.last_trick)
  const [seenKey, setSeenKey] = useState(lastKey)
  const [sweep, setSweep] = useState<Sweep | null>(null)

  // Derive the sweep in render, so no frame shows the empty stik first.
  if (seenKey !== lastKey) {
    setSeenKey(lastKey)
    const winner = view.last_trick_winner
    setSweep(
      lastKey !== "" && winner !== null && !reduced
        ? { key: lastKey, plays: view.last_trick, winner, stage: "resting" }
        : null,
    )
  }

  const nextStarted = view.current_trick.length > 0
  useEffect(() => {
    if (!sweep) return
    const key = sweep.key
    if (sweep.stage === "resting") {
      const wait = FLY_MS + (nextStarted ? 0 : PAUSE_MS)
      const timer = setTimeout(() => setSweep((s) => (s?.key === key ? { ...s, stage: "leaving" } : s)), wait)
      return () => clearTimeout(timer)
    }
    const timer = setTimeout(() => setSweep((s) => (s?.key === key ? null : s)), SWEEP_MS)
    return () => clearTimeout(timer)
  }, [sweep, nextStarted])

  // Cards already on the table when this mounts (page load) do not fly in.
  const initialCards = useRef(new Set(view.current_trick.map((play) => play.card)))
  useEffect(() => initialCards.current.clear(), [])

  const plays = sweep ? sweep.plays : view.current_trick
  const bySlot = new Map(plays.map((play) => [positionOf(play.seat), play]))
  const sweepTarget = sweep?.stage === "leaving" ? sweep.winner : null

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
                sweepTo={sweepTarget === null ? null : () => seatRect(sweepTarget)}
              />
            )}
          </div>
        )
      })}
    </div>
  )
}

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
      { x: [there.x - here.x, 0], y: [there.y - here.y, 0], scale: [from.scale, 1] },
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
