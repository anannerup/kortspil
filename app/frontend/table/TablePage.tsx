import { useEffect, useRef, useState } from "react"
import { Card, CardBack, parseCardCode, type CardCode } from "~/cards"
import type { SeatIndex, SeatInfo, ServerMessage, TableState, TrickPlay } from "./messages"
import { RundeResult, GameOver, ScoreSheet } from "./ScoreSheet"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { PASS_INSTRUCTIONS, REJECTIONS, joinNames, pointsLabel } from "./texts"
import "./table.css"

type Position = "south" | "west" | "north" | "east"
const POSITIONS: Position[] = ["south", "west", "north", "east"]
const PASS_SIZE = 3
const LOBBY_PATH = "/"

/**
 * The live table: renders the state the server sends and sends intents.
 * The layout is static: every region has a fixed size, and whatever comes
 * and goes (notices, the pass, results, the score sheet) is an overlay or
 * fills reserved space, so nothing moves during play.
 */
export function TablePage({ tableId, departurePath }: { tableId: number; departurePath: string }) {
  const [state, setState] = useState<TableState | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [selected, setSelected] = useState<CardCode[]>([])
  const [showScore, setShowScore] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const subscription = useRef<TableSubscription | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)

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
  useEffect(() => setSelected([]), [rundeKey])

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
  const play = (card: CardCode) => subscription.current?.send("play", { card })
  const leave = () => (finished ? leaveForm.current?.requestSubmit() : setConfirmLeave(true))

  return (
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
                  : "Klik på 3 kort i din hånd."}
              </span>
            </div>
          ) : (
            <Trick view={view} positionOf={positionOf} />
          )}
          <p className="table-caption">{centerCaption(state, nameOf)}</p>
        </div>

        <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
          {notice}
        </p>

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
        <div className="hf-hand" role="group" aria-label="Din hånd">
          {view.hand.map((code) => {
            if (choosing) {
              const isSelected = selected.includes(code)
              const full = selected.length >= PASS_SIZE
              return (
                <Card
                  key={code}
                  {...parseCardCode(code)}
                  state={isSelected ? "selected" : full ? "idle" : "playable"}
                  onClick={() => toggle(code)}
                />
              )
            }
            if (passing) return <Card key={code} {...parseCardCode(code)} state={ownPass.has(code) ? "selected" : "idle"} />
            const playable = myTurn && legal.has(code)
            return (
              <Card
                key={code}
                {...parseCardCode(code)}
                state={playable ? "playable" : myTurn ? "disabled" : "idle"}
                isNew={received.has(code)}
                onClick={playable ? () => play(code) : undefined}
              />
            )
          })}
        </div>
      </div>

      <div className={`table-self${myTurn ? " is-active" : ""}`}>
        <span className="table-seat-name">{nameOf(me)} (dig)</span>
        <span className="table-seat-meta">{pointsLabel(state.points_taken[me] ?? 0)} i runden</span>
      </div>

      {showScore && <ScoreSheet seats={seats} score={score} onClose={() => setShowScore(false)} />}
    </section>
  )
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

function statusText(state: TableState, nameOf: (seat: SeatIndex | null) => string): string {
  const { view } = state
  switch (view.phase) {
    case "passing":
      return view.passed_seats.includes(view.seat) ? "Du har givet dine kort." : "Vælg 3 kort at give væk."
    case "complete":
      return state.status === "finished" ? "Spillet er slut." : "Runden er slut."
    case "playing": {
      const turn = view.to_act === view.seat ? "Din tur." : `Venter på ${nameOf(view.to_act)}…`
      return view.hearts_broken ? `${turn} Hjerter er brudt.` : turn
    }
  }
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
}) {
  const { seat, position, cards, active, points, passState } = props
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
      <div className="table-backs" aria-hidden="true">
        {Array.from({ length: cards }, (_, index) => (
          <CardBack key={index} size="xs" />
        ))}
      </div>
    </div>
  )
}

/** The stik in the middle: four fixed slots. Between stik it shows the last one, faded. */
function Trick({ view, positionOf }: { view: TableState["view"]; positionOf: (seat: SeatIndex) => Position }) {
  const showingLast = view.current_trick.length === 0 && view.last_trick.length > 0
  const plays: TrickPlay[] = showingLast ? view.last_trick : view.current_trick
  const bySlot = new Map(plays.map((play) => [positionOf(play.seat), play.card]))
  return (
    <div className={`table-trick${showingLast ? " is-faded" : ""}`} role="group" aria-label={showingLast ? "Sidste stik" : "Stikket"}>
      {POSITIONS.map((position) => {
        const card = bySlot.get(position)
        return (
          <div key={position} className={`table-trick-slot table-slot-${position}`}>
            {card ? <Card {...parseCardCode(card)} /> : <div className="table-slot-empty" />}
          </div>
        )
      })}
    </div>
  )
}
