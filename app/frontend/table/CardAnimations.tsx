import { memo, useEffect, useLayoutEffect, useRef, type RefObject } from "react"
import { animate } from "motion/react"
import { Card, CardBack, parseCardCode, type CardCode } from "~/cards"
import type { PassDirection, SeatIndex } from "./messages"
import { giverOf, receiverOf } from "./passing"
import { FLY_MS, GIVE_MS, SWEEP_MS, TAKE_MS } from "./timeline"

/**
 * The card animations at the table, all presentational (Motion) and all
 * moved with transforms only, from rects measured when they start, so the
 * layout never changes:
 *
 * - flying in (useFlyIn): a card slides from where it was to where it now
 *   lies: hand to pass slot and back.
 * - into the stik (useFlyIntoTrick): a played card flies from its seat (or
 *   from where you tapped it) into its slot.
 * - the sweep (useSweep): the completed stik slides off to its winner.
 * - the bytning (PassFlights): the other seats' pass over the felt.
 *
 * timeline.ts decides when each happens and how long it takes.
 */

/** Where a card flies in from: a screen rect and the scale it starts at there. */
export interface FlightSource {
  rect: DOMRect
  /** Leave out to start at the rect's own size. */
  scale?: number
}

const center = (rect: DOMRect) => ({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 })

/**
 * On mount, slides the element from `from` to where it lies, with transform
 * only. The element must carry no other transform of its own (wrap it).
 */
export function useFlyIn(
  ref: RefObject<HTMLElement | null>,
  from: () => FlightSource | null,
  transition: { duration: number; ease: readonly number[] },
) {
  useLayoutEffect(() => {
    const element = ref.current
    const source = from()
    if (!element || !source) return
    const here = center(element.getBoundingClientRect())
    const there = center(source.rect)
    const rect = element.getBoundingClientRect()
    const scale = source.scale ?? (rect.width > 0 ? source.rect.width / rect.width : 1)
    const controls = animate(
      element,
      { x: [there.x - here.x, 0], y: [there.y - here.y, 0], scale: [scale, 1] },
      { duration: transition.duration, ease: [...transition.ease] as [number, number, number, number] },
    )
    return () => controls.stop()
  }, []) // On mount only: a card flies in once.
}

/** On mount, a card played into the stik flies into its slot from `from` (none: it does not fly). */
export function useFlyIntoTrick(ref: RefObject<HTMLElement | null>, from: () => FlightSource | null) {
  useLayoutEffect(() => {
    const element = ref.current
    const source = from()
    if (!element || !source) return
    element.style.transform = "none"
    const here = center(element.getBoundingClientRect())
    const there = center(source.rect)
    const controls = animate(
      element,
      { x: [there.x - here.x, 0], y: [there.y - here.y, 0], scale: [source.scale ?? source.rect.width / (element.getBoundingClientRect().width || 1), 1] },
      { duration: FLY_MS / 1000, ease: [0.2, 0.8, 0.25, 1] },
    )
    return () => controls.stop()
  }, []) // On mount only: a card flies in once.
}

/** Once `to` is given, the stik card slides off to its winner's seat and fades. */
export function useSweep(ref: RefObject<HTMLElement | null>, to: (() => DOMRect | null) | null) {
  const sweeping = to !== null
  useEffect(() => {
    const element = ref.current
    const target = to?.()
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
}

const STAGGER = 0.05
const PASS_SIZE = 3

/**
 * The other seats' side of the bytning, drawn over the felt (yours is in
 * PassCentre and in your hand):
 *
 * - "give": each opponent's three cards slide face down from their hand to
 *   the pile in front of the seat that gets them (yours too).
 * - "take": the piles in front of the opponents slide into their hands;
 *   the pile they got from you shows your cards face up.
 */
export const PassFlights = memo(function PassFlights(props: {
  stage: "give" | "take"
  me: SeatIndex
  direction: PassDirection
  ownPass: CardCode[]
  /** Where a seat's hand is on screen. */
  seatRect: (seat: SeatIndex) => DOMRect | null
  /** Where the pile in front of a seat lies. */
  pileRect: (seat: SeatIndex) => DOMRect | null
}) {
  const { stage, me, direction, ownPass, seatRect, pileRect } = props
  const others = [0, 1, 2, 3].filter((seat) => seat !== me)
  return (
    <div className="table-pass-flights" aria-hidden="true">
      {stage === "give"
        ? others.flatMap((giver) =>
            Array.from({ length: PASS_SIZE }, (_, index) => (
              <Flying
                key={`give-${giver}-${index}`}
                index={index}
                start={() => seatRect(giver)}
                end={() => pileRect(receiverOf(giver, direction))}
                duration={GIVE_MS}
                fade={false}
              />
            )),
          )
        : others.flatMap((receiver) => {
            const fromMe = giverOf(receiver, direction) === me
            return Array.from({ length: PASS_SIZE }, (_, index) => (
              <Flying
                key={`take-${receiver}-${index}`}
                index={index}
                start={() => pileRect(receiver)}
                end={() => seatRect(receiver)}
                duration={TAKE_MS}
                fade
                card={fromMe ? ownPass[index] : undefined}
              />
            ))
          })}
    </div>
  )
})

/** One card of the bytning moving from `start` to `end`, a little after the one before it. */
function Flying(props: {
  index: number
  start: () => DOMRect | null
  end: () => DOMRect | null
  duration: number
  fade: boolean
  card?: CardCode
}) {
  const { index, start, end, duration, fade, card } = props
  const ref = useRef<HTMLDivElement | null>(null)
  useLayoutEffect(() => {
    const element = ref.current
    const from = start()
    const to = end()
    if (!element || !from || !to) return
    // Sit on the start, then move by transform to the end. A pile spreads a little.
    const size = element.getBoundingClientRect().width
    const spread = (index - 1) * size * 0.18
    element.style.left = `${center(from).x - size / 2}px`
    element.style.top = `${center(from).y - size * 0.715}px`
    // The pile is spread and tilted a little: at the end of "give", at the start of "take".
    const tilt = (index - 1) * 6
    const dx = center(to).x - center(from).x
    const dy = center(to).y - center(from).y
    const controls = animate(
      element,
      fade
        ? { x: [spread, dx], y: [0, dy], rotate: [tilt, 0], opacity: [1, 1, 0] }
        : { x: [0, dx + spread], y: [0, dy], rotate: [0, tilt], opacity: [0, 1, 1] },
      { duration: duration / 1000 - 2 * STAGGER, delay: index * STAGGER, ease: [0.3, 0.1, 0.4, 1] },
    )
    return () => controls.stop()
  }, []) // Once, as the step starts.
  return (
    <div ref={ref} className="table-pass-flying">
      {card ? <Card {...parseCardCode(card)} size="sm" /> : <CardBack size="sm" />}
    </div>
  )
}
