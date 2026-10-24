import { useRef } from "react"
import { AnimatePresence, motion } from "motion/react"
import { Card, parseCardCode, type CardCode, type Suit } from "~/cards"
import type { SeatView } from "./messages"

export const PASS_SIZE = 3
export const suitOf = (code: CardCode) => parseCardCode(code).suit

// Motion timings (s), shared with PassCentre so cards move as one.
export const CARD_MOVE = { type: "tween", duration: 0.32, ease: [0.25, 0.8, 0.3, 1] } as const
const FADE = { duration: 0.18 }

/**
 * Your hand, as the bridge app on iPad does it:
 *
 * - In play it is a fan. On your turn the first tap picks a suit: the other
 *   cards fade away and that suit's cards glide out, big, in a row just
 *   under the stik. The second tap plays one of them; it flies into the
 *   stik from where it lies (Trick). "Fortryd" puts the fan back.
 * - In the pass a tap moves the card to the middle of the table
 *   (PassCentre); a tap there brings it back. Each card keeps one
 *   `layoutId`, so it glides between fan, row and slots.
 *
 * Which cards may be played comes from the server (legal_moves); a suit
 * without any shows its cards greyed out.
 */
export function Hand(props: {
  view: SeatView
  /** The suit picked with the first tap, or null for the fan. */
  pickedSuit: Suit | null
  onPickSuit: (suit: Suit) => void
  /** The second tap; the element's rect is where the card flies from. */
  onPlay: (card: CardCode, from: DOMRect | null) => void
  /** Cards chosen for the pass (they sit in the middle, not in the fan). */
  passSelection: CardCode[]
  onTogglePass: (card: CardCode) => void
  /** The card just played: it leaves without fading, as Trick takes it over. */
  playedCard: CardCode | null
}) {
  const { view, pickedSuit, onPickSuit, onPlay, passSelection, onTogglePass, playedCard } = props
  const myTurn = view.phase === "playing" && view.to_act === view.seat
  const choosingPass = view.phase === "passing" && !view.passed_seats.includes(view.seat)
  const passing = view.phase === "passing"
  const legal = new Set(view.legal_moves)
  const received = new Set(view.received_cards)
  const picking = myTurn && pickedSuit !== null

  const away = new Set(choosingPass ? passSelection : passing ? view.own_pass : [])
  const cards = view.hand.filter((code) => !away.has(code) && (!picking || suitOf(code) === pickedSuit))
  const mid = (cards.length - 1) / 2
  const full = choosingPass && passSelection.length >= PASS_SIZE

  return (
    <div className={`table-hand${picking ? " is-picking" : ""}${myTurn ? " is-turn" : ""}`}>
      <AnimatePresence initial={false} custom={[...passSelection, ...(playedCard ? [playedCard] : [])]}>
        {cards.map((code, index) => {
          const offset = index - mid
          const tap = choosingPass ? (full ? undefined : () => onTogglePass(code)) : myTurn && !picking ? () => onPickSuit(suitOf(code)) : undefined
          return (
            <HandCard
              key={code}
              code={code}
              rotate={picking ? 0 : offset * 3.2}
              lift={picking ? 0 : offset * offset * 1.1}
              picking={picking}
              legal={legal.has(code)}
              isNew={received.has(code)}
              onTap={tap}
              onPlay={onPlay}
            />
          )
        })}
      </AnimatePresence>
    </div>
  )
}

// Cards that move on (to the stik or a pass slot) leave at once; the rest fade.
const exitFor = (movingOn: CardCode[], code: CardCode) =>
  movingOn.includes(code) ? { opacity: 0, transition: { duration: 0 } } : { opacity: 0, y: 40, transition: FADE }

function HandCard(props: {
  code: CardCode
  rotate: number
  lift: number
  picking: boolean
  legal: boolean
  isNew: boolean
  onTap: (() => void) | undefined
  onPlay: (card: CardCode, from: DOMRect | null) => void
}) {
  const { code, rotate, lift, picking, legal, isNew, onTap, onPlay } = props
  const ref = useRef<HTMLDivElement>(null)
  const card = parseCardCode(code)
  const content = picking ? (
    <Card
      {...card}
      state={legal ? "playable" : "disabled"}
      onClick={legal ? () => onPlay(code, ref.current?.getBoundingClientRect() ?? null) : undefined}
    />
  ) : (
    <Card {...card} state={onTap ? "playable" : "idle"} isNew={isNew} onClick={onTap} />
  )
  return (
    <motion.div
      ref={ref}
      layoutId={`hand-${code}`}
      className="table-hand-card"
      initial={{ opacity: 0, y: 40, rotate, scale: 1 }}
      animate={{ opacity: 1, y: lift, rotate }}
      variants={{ leave: (movingOn: CardCode[]) => exitFor(movingOn, code) }}
      exit="leave"
      transition={CARD_MOVE}
    >
      {content}
    </motion.div>
  )
}
