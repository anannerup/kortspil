import { useEffect, useRef, useState, type ReactNode } from "react"
import { MotionConfig, motion, useReducedMotion } from "motion/react"
import { Card, CardBack, parseCardCode, type CardCode } from "~/cards"
import type { SeatIndex, SeatInfo, ServerMessage, TableState, TrickPlay } from "./messages"
import { RundeResult, GameOver, MoonChoice, ScoreSheet } from "./ScoreSheet"
import { statusText } from "./status"
import { LastTrick, POSITIONS, Trick, type FlightSource, type Position } from "./Trick"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { PASS_INSTRUCTIONS, REJECTIONS, joinNames, pointsLabel } from "./texts"
import "./table.css"
// PROTOTYPE (throwaway): ?variant=A|B|C renders a layout prototype instead, dev only.
import { PROTOTYPE_VARIANTS, VariantA, VariantB, VariantC } from "./prototype/TablePrototypes"
import { PrototypeSwitcher } from "./prototype/PrototypeSwitcher"

const PASS_SIZE = 3
const LOBBY_PATH = "/"

/**
 * The live table: renders the state the server sends and sends intents.
 * The layout is static: every region has a fixed size, and whatever comes
 * and goes (notices, the pass, results, the score sheet) is an overlay or
 * fills reserved space, so nothing moves during play. Animations move
 * cards with transform and opacity only (Motion); they are presentational
 * and never hold back the state shown in the hand.
 */
export function TablePage({ tableId, departurePath }: { tableId: number; departurePath: string }) {
  const [state, setState] = useState<TableState | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [selected, setSelected] = useState<CardCode[]>([])
  const [showScore, setShowScore] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const reducedMotion = useReducedMotion() ?? false
  const subscription = useRef<TableSubscription | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)
  // Screen anchors for card flights: seats (opponents' card backs, your own
  // seat), hand cards, and where your played card was when you clicked it.
  const seatEls = useAnchors<SeatIndex>()
  const handEls = useAnchors<CardCode>()
  const playedFrom = useRef(new Map<CardCode, DOMRect>())

  useEffect(() => {
    const handle = (message: ServerMessage) => {
      if (message.type === "closed") {
        window.location.assign(LOBBY_PATH)
        return
      }
      if (message.type === "rejected") {
        setNotice(REJECTIONS[message.reason] ?? "Trækket blev afvist.")
        return
      }
      setNotice(null)
      setState((current) => (current && isNewer(current, message.state) ? current : message.state))
    }
    subscription.current = subscribeToTable(tableId, {
      onMessage: handle,
      onConnectionChange: setConnected,
      onRejected: () => setRefused(true),
    })
    return () => subscription.current?.close()
  }, [tableId])

  // A new runde or spil starts with nothing selected.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setSelected([])
    playedFrom.current.clear()
  }, [rundeKey])

  if (refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state) return <p className="table-loading">Henter bordet…</p>

  const { view, seats, score } = state
  const me = view.seat
  const positionOf = (seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south"
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const passing = view.phase === "passing"
  const passed = view.passed_seats.includes(me)
  const choosing = passing && !passed
  const myTurn = view.to_act === me
  const legal = new Set(view.legal_moves)
  const received = new Set(view.received_cards)
  const ownPass = new Set(view.own_pass)
  const finished = state.status === "finished"

  const toggle = (code: CardCode) =>
    setSelected((current) =>
      current.includes(code)
        ? current.filter((card) => card !== code)
        : current.length < PASS_SIZE
          ? [...current, code]
          : current,
    )
  const pass = () => subscription.current?.send("pass", { cards: selected })
  const play = (card: CardCode) => {
    const rect = handEls.get(card)?.getBoundingClientRect()
    if (rect) playedFrom.current.set(card, rect)
    subscription.current?.send("play", { card })
  }
  const seatRect = (seat: SeatIndex) => seatEls.get(seat)?.getBoundingClientRect() ?? null
  const flightSource = (trickPlay: TrickPlay): FlightSource | null => {
    const own = trickPlay.seat === me ? playedFrom.current.get(trickPlay.card) : undefined
    if (own) return { rect: own, scale: 1 }
    const rect = seatRect(trickPlay.seat)
    return rect ? { rect, scale: 0.45 } : null
  }
  const leave = () => (finished ? leaveForm.current?.requestSubmit() : setConfirmLeave(true))

  // PROTOTYPE (throwaway): layout variants on the same state and intents.
  const variant = import.meta.env.DEV ? new URLSearchParams(window.location.search).get("variant") : null
  const variants = [{ key: "nu", name: "Nuværende bord" }, ...PROTOTYPE_VARIANTS]
  if (variant && variant !== "nu") {
    const Variant = { A: VariantA, B: VariantB, C: VariantC }[variant] ?? VariantA
    return (
      <>
        <Variant
          state={state}
          notice={notice}
          connected={connected}
          selected={selected}
          toggle={toggle}
          pass={pass}
          play={play}
          nextRunde={() => subscription.current?.send("next_runde", {})}
          playAgain={() => subscription.current?.send("play_again", {})}
          chooseMoon={(option) => subscription.current?.send("choose_moon", { option })}
          leaveNow={() => leaveForm.current?.requestSubmit()}
        />
        <form ref={leaveForm} method="post" action={departurePath} hidden>
          <input type="hidden" name="authenticity_token" value={csrfToken()} />
        </form>
        <PrototypeSwitcher variants={variants} current={variant} />
      </>
    )
  }

  const renderHandCard = (code: CardCode): ReactNode => {
    if (choosing) {
      const isSelected = selected.includes(code)
      const full = selected.length >= PASS_SIZE
      return (
        <Card
          {...parseCardCode(code)}
          state={isSelected ? "selected" : full ? "idle" : "playable"}
          onClick={() => toggle(code)}
        />
      )
    }
    if (passing) return <Card {...parseCardCode(code)} state={ownPass.has(code) ? "selected" : "idle"} />
    const playable = myTurn && legal.has(code)
    return (
      <Card
        {...parseCardCode(code)}
        state={playable ? "playable" : myTurn ? "disabled" : "idle"}
        isNew={received.has(code)}
        onClick={playable ? () => play(code) : undefined}
      />
    )
  }

  return (
    <MotionConfig reducedMotion="user">
    <section className="table-page" aria-label={`Bord ${state.table_id}`}>
      <header className="table-header">
        <h1>Øvebord · Runde {state.round_number}</h1>
        <span className={`table-offline${connected ? " is-hidden" : ""}`}>Forbinder…</span>
        <button type="button" onClick={() => setShowScore(true)}>
          Stilling
        </button>
        <div className="table-leave">
          <button type="button" className="table-leave-button" onClick={leave}>
            Forlad bordet
          </button>
          <form ref={leaveForm} method="post" action={departurePath} className={`table-leave-confirm${confirmLeave ? "" : " is-hidden"}`}>
            <input type="hidden" name="authenticity_token" value={csrfToken()} />
            <p>Forlad bordet? Du taber spillet.</p>
            <button type="submit">Ja</button>
            <button type="button" onClick={() => setConfirmLeave(false)}>
              Nej
            </button>
          </form>
        </div>
      </header>

      <div className="table-board">
        {seats
          .filter((seat) => seat.seat !== me)
          .map((seat) => (
            <Opponent
              key={seat.seat}
              seat={seat}
              position={positionOf(seat.seat)}
              cards={view.card_counts[String(seat.seat)] ?? 0}
              active={view.to_act === seat.seat}
              points={state.points_taken[seat.seat] ?? 0}
              passState={passing ? (view.passed_seats.includes(seat.seat) ? "Har givet kort" : "Vælger kort…") : ""}
              backsRef={seatEls.ref(seat.seat)}
            />
          ))}

        <div className="table-center">
          {passing ? (
            <div className="table-pass-info">
              <strong>{PASS_INSTRUCTIONS[view.pass_direction]}</strong>
              {view.pass_direction !== "none" && <span>til {nameOf(receiverOf(me, view.pass_direction))}</span>}
              <span>
                {passed
                  ? `Venter på ${joinNames(seats.filter((seat) => !view.passed_seats.includes(seat.seat)).map((seat) => seat.name))}…`
                  : "Vælg 3 kort i din hånd."}
              </span>
            </div>
          ) : (
            <Trick view={view} positionOf={positionOf} source={flightSource} seatRect={seatRect} />
          )}
          <p className="table-caption">{centerCaption(state, nameOf)}</p>
        </div>

        <LastTrick view={view} nameOf={nameOf} />

        <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
          {notice}
        </p>

        {view.phase === "choosing_moon" && (
          <MoonChoice state={state} onChoose={(option) => subscription.current?.send("choose_moon", { option })} />
        )}
        {view.phase === "complete" && !finished && (
          <RundeResult state={state} onNext={() => subscription.current?.send("next_runde", {})} />
        )}
        {view.phase === "complete" && finished && (
          <GameOver
            state={state}
            onPlayAgain={() => subscription.current?.send("play_again", {})}
            onLeave={() => leaveForm.current?.requestSubmit()}
          />
        )}
      </div>

      <div className="table-actions">
        <p className="table-status" aria-live="polite">
          {statusText(state, nameOf)}
        </p>
        <div className={`table-pass-controls${choosing ? "" : " is-hidden"}`}>
          <span>
            {selected.length} af {PASS_SIZE} valgt
          </span>
          <button type="button" disabled={!choosing || selected.length !== PASS_SIZE} onClick={pass}>
            Giv kortene
          </button>
        </div>
      </div>

      <div className="table-hand-row">
        {/* The hand is shown in the server's order (sorted by suit and rank).
            Each card slides into place when the hand changes and fades up
            when dealt or received; both with transform and opacity only. */}
        <div className="hf-hand" role="group" aria-label="Din hånd" key={rundeKey}>
          {view.hand.map((code, index) => (
            <motion.div
              key={code}
              ref={handEls.ref(code)}
              className="table-hand-card"
              layout="position"
              initial={reducedMotion ? false : { opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.25, delay: Math.min(index, 12) * 0.03, layout: { duration: 0.22 } }}
            >
              {renderHandCard(code)}
            </motion.div>
          ))}
        </div>
      </div>

      <div ref={seatEls.ref(me)} className={`table-self${myTurn ? " is-active" : ""}`}>
        <span className="table-seat-name">{nameOf(me)} (dig)</span>
        <span className="table-seat-meta">{pointsLabel(state.points_taken[me] ?? 0)} i runden</span>
      </div>

      {showScore && <ScoreSheet seats={seats} score={score} rules={state.rules} onClose={() => setShowScore(false)} />}
      {import.meta.env.DEV && <PrototypeSwitcher variants={[{ key: "nu", name: "Nuværende bord" }, ...PROTOTYPE_VARIANTS]} current="nu" />}
    </section>
    </MotionConfig>
  )
}

/**
 * Elements by key, for measuring where a card flies from or to. The ref
 * callbacks are stable per key, so React never detaches them on re-render.
 */
function useAnchors<K>() {
  const [{ elements, refs }] = useState(() => ({
    elements: new Map<K, HTMLElement>(),
    refs: new Map<K, (element: HTMLElement | null) => void>(),
  }))
  return {
    get: (key: K) => elements.get(key),
    ref: (key: K) => {
      let callback = refs.get(key)
      if (!callback) {
        callback = (element) => {
          if (element) elements.set(key, element)
          else elements.delete(key)
        }
        refs.set(key, callback)
      }
      return callback
    },
  }
}

/** Ignore a state older than the one shown (messages can cross on the wire). */
function isNewer(current: TableState, incoming: TableState): boolean {
  return current.game_id === incoming.game_id && current.version > incoming.version
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}

/** Who gets this seat's pass: seats sit clockwise, left is the next seat. */
function receiverOf(seat: SeatIndex, direction: "left" | "right" | "across"): SeatIndex {
  const offset = { left: 1, right: 3, across: 2 }[direction]
  return (seat + offset) % 4
}

function centerCaption(state: TableState, nameOf: (seat: SeatIndex | null) => string): string {
  const { view } = state
  if (view.phase === "passing") return ""
  const noTrickYet = view.current_trick.length === 0 && view.last_trick.length === 0
  if (noTrickYet && view.received_cards.length > 0) return "Dine nye kort er markeret med guld."
  if (noTrickYet && view.pass_direction === "none") return "Ingen bytning denne runde."
  if (view.current_trick.length === 0 && view.last_trick_winner !== null) return `${nameOf(view.last_trick_winner)} tog stikket`
  return ""
}

function Opponent(props: {
  seat: SeatInfo
  position: Position
  cards: number
  active: boolean
  points: number
  passState: string
  backsRef: (element: HTMLElement | null) => void
}) {
  const { seat, position, cards, active, points, passState, backsRef } = props
  return (
    <div className={`table-opponent table-${position}${active ? " is-active" : ""}`}>
      <span className="table-seat-name">
        {seat.name}
        {seat.bot && <span className="table-bot"> (bot)</span>}
      </span>
      <span className="table-seat-meta">
        {cards} kort · {pointsLabel(points)} i runden
      </span>
      <span className="table-seat-meta">{passState}</span>
      <div ref={backsRef} className="table-backs" aria-hidden="true">
        {Array.from({ length: cards }, (_, index) => (
          <CardBack key={index} size="xs" />
        ))}
      </div>
    </div>
  )
}
