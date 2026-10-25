import { memo, useLayoutEffect, useRef } from "react"
import { animate } from "motion/react"
import { Card, CardBack, parseCardCode, type CardCode } from "~/cards"
import type { PassDirection, SeatIndex } from "./messages"
import { giverOf, receiverOf } from "./passing"
import { GIVE_MS, TAKE_MS } from "./timeline"

const STAGGER = 0.05
const PASS_SIZE = 3

/**
 * The other seats' side of the pass, drawn over the felt (yours is in
 * PassCentre and in your hand):
 *
 * - "give": each opponent's three cards slide face down from their hand to
 *   the pile in front of the seat that gets them (yours too).
 * - "take": the piles in front of the opponents slide into their hands;
 *   the pile they got from you shows your cards face up.
 *
 * Everything is placed and moved with fixed positions and transforms, from
 * rects measured when it starts.
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

const center = (rect: DOMRect) => ({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 })

/** One card moving from `start` to `end`, a little after the one before it. */
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
