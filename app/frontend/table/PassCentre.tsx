import { useEffect, useRef } from "react"
import { animate } from "motion/react"
import { Card, parseCardCode, type CardCode } from "~/cards"
import { useFlyIn, type FlightSource } from "./CardAnimations"
import type { SeatIndex, SeatInfo, SeatView } from "./messages"
import { CARD_MOVE, PASS_SIZE } from "./Hand"
import { receiverOf } from "./passing"
import { PASS_INSTRUCTIONS, joinNames } from "./texts"
import { GIVE_MS } from "./timeline"


/**
 * The pass, in the middle of the table: where the cards go, three slots the
 * chosen cards glide into from the hand (a tap sends one back), and the
 * button. Once passed: your three cards and who we are waiting for.
 */
export function PassCentre(props: {
  view: SeatView
  seats: SeatInfo[]
  selection: CardCode[]
  onToggle: (card: CardCode, from: DOMRect | null) => void
  onPass: () => void
  /** Where a card chosen in the hand flies in from. */
  from: (card: CardCode) => FlightSource | null
  /** Once every seat has passed: the pile in front of your receiver, where your cards slide to. */
  giveTo: (() => DOMRect | null) | null
}) {
  const { view, seats, selection, onToggle, onPass, from, giveTo } = props
  const passed = view.passed_seats.includes(view.seat)
  // Once passed, the cards stay in the order you laid them (the server sorts them).
  const cards = passed ? [...view.own_pass].sort((a, b) => order(selection, a) - order(selection, b)) : selection
  const receiver = seats[receiverOf(view.seat, view.pass_direction)]?.name ?? ""
  const waiting = seats.filter((seat) => !view.passed_seats.includes(seat.seat)).map((seat) => seat.name)

  return (
    <div className="table-pass">
      <strong className="table-pass-title">
        {PASS_INSTRUCTIONS[view.pass_direction]}
        <span> · {receiver}</span>
      </strong>
      <div className="table-pass-slots">
        {Array.from({ length: PASS_SIZE }, (_, index) => {
          const code = cards[index]
          return (
            <div key={index} className="table-pass-slot">
              {code && <SlotCard key={code} code={code} index={index} passed={passed} onToggle={onToggle} from={from} giveTo={giveTo} />}
            </div>
          )
        })}
      </div>
      {passed ? (
        <span className="table-pass-wait">{waiting.length > 0 ? `Venter på ${joinNames(waiting)}…` : "Kortene byttes…"}</span>
      ) : (
        <button type="button" className="table-btn table-btn-primary table-btn-xl" disabled={selection.length !== PASS_SIZE} onClick={onPass}>
          {selection.length === PASS_SIZE ? "Giv kortene" : `Vælg ${PASS_SIZE - selection.length} kort mere`}
        </button>
      )}
    </div>
  )
}

const order = (selection: CardCode[], card: CardCode) => {
  const index = selection.indexOf(card)
  return index === -1 ? PASS_SIZE : index
}

/** A chosen card in its slot: it flies in from the hand, a tap sends it back. */
function SlotCard(props: {
  code: CardCode
  index: number
  passed: boolean
  onToggle: (card: CardCode, from: DOMRect | null) => void
  from: (card: CardCode) => FlightSource | null
  giveTo: (() => DOMRect | null) | null
}) {
  const { code, index, passed, onToggle, from, giveTo } = props
  const ref = useRef<HTMLDivElement | null>(null)
  useFlyIn(ref, () => from(code), CARD_MOVE)
  // The three cards slide, one just after another, to the pile in front
  // of their receiver, and lie there until it picks them up.
  const giving = giveTo !== null
  useEffect(() => {
    const element = ref.current
    const target = giveTo?.()
    if (!element || !target) return
    const here = element.getBoundingClientRect()
    const scale = target.width / here.width
    const spread = (index - 1) * target.width * 0.18
    const dx = target.left + target.width / 2 + spread - (here.left + here.width / 2)
    const dy = target.top + target.height / 2 - (here.top + here.height / 2)
    const stagger = 0.05
    const controls = animate(
      element,
      { x: dx, y: dy, scale, rotate: (index - 1) * 6 },
      { duration: GIVE_MS / 1000 - 2 * stagger, delay: index * stagger, ease: [0.3, 0.1, 0.4, 1] },
    )
    return () => controls.stop()
  }, [giving]) // Once, when the cards are given.
  return (
    <div ref={ref}>
      <Card
        {...parseCardCode(code)}
        state={passed ? "idle" : "playable"}
        onClick={passed ? undefined : () => onToggle(code, ref.current?.getBoundingClientRect() ?? null)}
      />
    </div>
  )
}
