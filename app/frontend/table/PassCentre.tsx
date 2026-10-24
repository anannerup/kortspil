import { motion } from "motion/react"
import { Card, parseCardCode, type CardCode } from "~/cards"
import type { SeatIndex, SeatInfo, SeatView } from "./messages"
import { CARD_MOVE, PASS_SIZE } from "./Hand"
import { PASS_INSTRUCTIONS, joinNames } from "./texts"

/** Who gets this seat's pass: seats sit clockwise, left is the next seat. */
export function receiverOf(seat: SeatIndex, direction: SeatView["pass_direction"]): SeatIndex {
  const offset = { left: 1, right: 3, across: 2, none: 0 }[direction]
  return (seat + offset) % 4
}

/**
 * The pass, in the middle of the table: where the cards go, three slots the
 * chosen cards glide into from the hand (a tap sends one back), and the
 * button. Once passed: your three cards and who we are waiting for.
 */
export function PassCentre(props: {
  view: SeatView
  seats: SeatInfo[]
  selection: CardCode[]
  onToggle: (card: CardCode) => void
  onPass: () => void
}) {
  const { view, seats, selection, onToggle, onPass } = props
  const passed = view.passed_seats.includes(view.seat)
  const cards = passed ? view.own_pass : selection
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
              {code && (
                <motion.div layoutId={`hand-${code}`} transition={CARD_MOVE}>
                  <Card
                    {...parseCardCode(code)}
                    state={passed ? "idle" : "playable"}
                    onClick={passed ? undefined : () => onToggle(code)}
                  />
                </motion.div>
              )}
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
