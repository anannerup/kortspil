import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { AnimatePresence, motion } from "motion/react"
import { Card, parseCardCode, type CardCode, type Suit } from "~/cards"
import { useFlyIn, type FlightSource } from "./flight"
import { fanSpots, rowSpots, type HandSize, type Spot } from "./handLayout"
import type { SeatView } from "./messages"

export const PASS_SIZE = 3
export const suitOf = (code: CardCode) => parseCardCode(code).suit

// Motion timings (s), shared with PassCentre so cards move as one: one short
// ease-out for every move, so a card starts at once and settles softly.
export const CARD_MOVE = { type: "tween", duration: 0.2, ease: [0.2, 0.75, 0.3, 1] } as const
const FADE = { type: "tween", duration: 0.14, ease: "easeOut" } as const
const DEAL_STAGGER = 0.035
const SINK = 40 // px a fading card sinks
const HOME: Spot = { x: 0, y: 0, rotate: 0, scale: 1 }

/**
 * Your hand, as the bridge app on iPad does it:
 *
 * - In play it is a fan. On your turn the first tap picks a suit: the other
 *   cards fade away and that suit's cards glide out, big, in a row just
 *   under the stik. The second tap plays one of them; it flies into the
 *   stik from where it lies (Trick). "Fortryd" puts the fan back.
 * - In the pass a tap sends the card to the middle of the table
 *   (PassCentre); a tap there brings it back.
 *
 * Every card lies on a spot from handLayout and moves by transform only.
 * Cards of other suits stay mounted while you pick, faded out, so nothing
 * is laid out again. Which cards may be played comes from the server
 * (legal_moves); a suit without any shows its cards greyed out.
 */
export const Hand = memo(function Hand(props: {
  view: SeatView
  /** The suit picked with the first tap, or null for the fan. */
  pickedSuit: Suit | null
  onPickSuit: (suit: Suit) => void
  /** The second tap; the rect is where the card flies from. */
  onPlay: (card: CardCode, from: DOMRect | null) => void
  /** Cards chosen for the pass (they sit in the middle, not in the fan). */
  passSelection: CardCode[]
  onTogglePass: (card: CardCode, from: DOMRect | null) => void
  /** The card just played: it leaves at once, as Trick takes it over. */
  playedCard: CardCode | null
  /** Where a card coming back from the pass slots flies in from. */
  returningFrom: (card: CardCode) => FlightSource | null
}) {
  const { view, pickedSuit, onPickSuit, onPlay, passSelection, onTogglePass, playedCard, returningFrom } = props
  const myTurn = view.phase === "playing" && view.to_act === view.seat
  const choosingPass = view.phase === "passing" && !view.passed_seats.includes(view.seat)
  const passing = view.phase === "passing"
  const picking = myTurn && pickedSuit !== null
  const legal = new Set(view.legal_moves)
  const received = new Set(view.received_cards)
  const away = new Set(choosingPass ? passSelection : passing ? view.own_pass : [])
  const full = choosingPass && passSelection.length >= PASS_SIZE

  const [size, sizeRef, rowRef] = useHandSize()
  const cards = view.hand.filter((code) => !away.has(code))
  const suit = picking ? cards.filter((code) => suitOf(code) === pickedSuit) : []
  // Spots only change with the number of cards or the size: reuse them.
  const fan = useMemo(() => (size ? fanSpots(cards.length, size) : []), [cards.length, size])
  const row = useMemo(() => (size ? rowSpots(suit.length, size) : []), [suit.length, size])
  const movingOn = [...passSelection, ...(playedCard ? [playedCard] : [])]

  return (
    <div ref={rowRef} className={`table-hand${picking ? " is-picking" : ""}${myTurn ? " is-turn" : ""}`}>
      <div ref={sizeRef} className="table-hand-sizer" aria-hidden="true" />
      {size && (
        <AnimatePresence initial={false} custom={movingOn}>
          {cards.map((code, index) => {
            const inRow = suit.indexOf(code)
            const hidden = picking && inRow === -1
            const spot = (inRow === -1 ? fan[index] : row[inRow]) ?? HOME
            const mode = picking ? (hidden ? "hidden" : legal.has(code) ? "play" : "locked") : choosingPass ? (full ? "idle" : "pass") : myTurn ? "pick" : "idle"
            return (
              <HandCard
                key={code}
                code={code}
                index={index}
                x={spot.x}
                y={spot.y}
                rotate={spot.rotate}
                scale={spot.scale}
                mode={mode}
                isNew={received.has(code)}
                onPickSuit={onPickSuit}
                onPlay={onPlay}
                onTogglePass={onTogglePass}
                returningFrom={returningFrom}
              />
            )
          })}
        </AnimatePresence>
      )}
    </div>
  )
})

/** The row's width and the card width, measured before paint and on resize. */
function useHandSize() {
  const sizer = useRef<HTMLDivElement | null>(null)
  const rowEl = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState<HandSize | null>(null)
  useLayoutEffect(() => {
    const measure = () => {
      const width = rowEl.current?.clientWidth ?? 0
      const cw = sizer.current?.offsetWidth ?? 0
      setSize((current) => (current && current.width === width && current.cw === cw ? current : { width, cw }))
    }
    measure()
    const observer = new ResizeObserver(measure)
    if (rowEl.current) observer.observe(rowEl.current)
    if (sizer.current) observer.observe(sizer.current)
    return () => observer.disconnect()
  }, [])
  return [size, sizer, rowEl] as const
}

// Cards that move on (to the stik or a pass slot) leave at once; the rest fade.
const exitFor = (movingOn: CardCode[], code: CardCode, y: number) =>
  movingOn.includes(code) ? { opacity: 0, transition: { duration: 0 } } : { opacity: 0, y: y + SINK, transition: FADE }

type Mode = "idle" | "pick" | "pass" | "play" | "locked" | "hidden"

const HandCard = memo(function HandCard(props: Spot & {
  code: CardCode
  /** Position in the fan: dealt cards come in one after another. */
  index: number
  mode: Mode
  isNew: boolean
  onPickSuit: (suit: Suit) => void
  onPlay: (card: CardCode, from: DOMRect | null) => void
  onTogglePass: (card: CardCode, from: DOMRect | null) => void
  returningFrom: (card: CardCode) => FlightSource | null
}) {
  const { code, index, x, y, rotate, scale, mode, isNew, onPickSuit, onPlay, onTogglePass, returningFrom } = props
  const face = useRef<HTMLDivElement | null>(null)
  // A card back from the pass slots flies in; a dealt one rises into place.
  const [returning] = useState(() => returningFrom(code) !== null)
  useFlyIn(face, () => returningFrom(code), CARD_MOVE)
  const mounted = useRef(false)
  useEffect(() => {
    mounted.current = true
  }, [])

  const hidden = mode === "hidden"
  const spot = { x, y: hidden ? y + SINK : y, rotate, scale, opacity: hidden ? 0 : 1 }
  const rect = () => face.current?.getBoundingClientRect() ?? null
  const card = parseCardCode(code)
  const onClick =
    mode === "pick" ? () => onPickSuit(card.suit) : mode === "pass" ? () => onTogglePass(code, rect()) : mode === "play" ? () => onPlay(code, rect()) : undefined
  const state = mode === "locked" ? "disabled" : onClick ? "playable" : "idle"

  return (
    <motion.div
      className="table-hand-card"
      initial={returning ? spot : { ...spot, y: spot.y + SINK, opacity: 0 }}
      animate={spot}
      transition={hidden ? FADE : { ...CARD_MOVE, delay: mounted.current ? 0 : index * DEAL_STAGGER }}
      variants={{ leave: (movingOn: CardCode[]) => exitFor(movingOn, code, y) }}
      exit="leave"
      style={{ pointerEvents: hidden ? "none" : undefined }}
    >
      <div ref={face}>
        <Card {...card} state={state} isNew={isNew && mode !== "play"} onClick={onClick} />
      </div>
    </motion.div>
  )
})
