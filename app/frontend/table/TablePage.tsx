import { useEffect, useRef, useState } from "react"
import { Card, CardBack, parseCardCode, type CardCode } from "~/cards"
import type { RejectionReason, SeatIndex, SeatInfo, ServerMessage, TableState, TrickPlay } from "./messages"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import "./table.css"

type Position = "south" | "west" | "north" | "east"
const POSITIONS: Position[] = ["south", "west", "north", "east"]

const REJECTIONS: Record<RejectionReason, string> = {
  round_complete: "Runden er slut.",
  unknown_intent: "Det kan du ikke her.",
  not_your_turn: "Det er ikke din tur.",
  card_not_in_hand: "Det kort har du ikke.",
  must_lead_two_of_clubs: "Du skal spille klør 2 ud.",
  must_follow_suit: "Du skal bekende kulør.",
  no_points_on_first_trick: "Du må ikke give point i første stik.",
  hearts_not_broken: "Hjerter er ikke brudt endnu.",
}

/** The live table: renders the state the server sends and sends play intents. */
export function TablePage({ tableId }: { tableId: number }) {
  const [state, setState] = useState<TableState | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const subscription = useRef<TableSubscription | null>(null)

  useEffect(() => {
    const handle = (message: ServerMessage) => {
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

  if (refused) return <p className="table-notice">Du sidder ikke ved dette bord.</p>
  if (!state) return <p className="table-status">Henter bordet…</p>

  const { view, seats } = state
  const me = view.seat
  const positionOf = (seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south"
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const play = (card: CardCode) => subscription.current?.send("play", { card })
  const legal = new Set(view.legal_moves)
  const myTurn = view.to_act === me
  const showingLastTrick = view.current_trick.length === 0 && view.last_trick.length > 0

  return (
    <section className="table-page" aria-label={`Bord ${state.table_id}`}>
      <header className="table-header">
        <h1>Øvebord · Runde {state.round_number}</h1>
        {!connected && <span className="table-offline">Forbinder…</span>}
      </header>

      <div className="table-grid">
        {seats
          .filter((seat) => seat.seat !== me)
          .map((seat) => (
            <Opponent
              key={seat.seat}
              seat={seat}
              position={positionOf(seat.seat)}
              cards={view.card_counts[String(seat.seat)] ?? 0}
              active={view.to_act === seat.seat}
            />
          ))}

        <div className="table-center">
          <Trick
            plays={showingLastTrick ? view.last_trick : view.current_trick}
            positionOf={positionOf}
            faded={showingLastTrick}
          />
          {showingLastTrick && <p className="table-caption">{nameOf(view.last_trick_winner)} tog stikket</p>}
        </div>
      </div>

      <p className="table-status" aria-live="polite">
        {view.phase === "complete"
          ? "Runden er slut."
          : myTurn
            ? "Din tur."
            : `Venter på ${nameOf(view.to_act)}…`}
        {view.hearts_broken && view.phase !== "complete" && " Hjerter er brudt."}
      </p>
      {notice && (
        <p className="table-notice" role="alert">
          {notice}
        </p>
      )}

      <div className={`table-seat-label${myTurn ? " is-active" : ""}`}>{nameOf(me)} (dig)</div>
      <div className="hf-hand" role="group" aria-label="Din hånd">
        {view.hand.map((code) => {
          const playable = myTurn && legal.has(code)
          return (
            <Card
              key={code}
              {...parseCardCode(code)}
              state={playable ? "playable" : myTurn ? "disabled" : "idle"}
              onClick={playable ? () => play(code) : undefined}
            />
          )
        })}
      </div>

      {view.phase === "complete" && <RoundPoints seats={seats} points={view.points} moonShooter={view.moon_shooter} />}
    </section>
  )
}

/** Ignore a state older than the one shown (messages can cross on the wire). */
function isNewer(current: TableState, incoming: TableState): boolean {
  return current.game_id === incoming.game_id && current.version > incoming.version
}

function Opponent({ seat, position, cards, active }: { seat: SeatInfo; position: Position; cards: number; active: boolean }) {
  return (
    <div className={`table-opponent table-${position}${active ? " is-active" : ""}`}>
      <div className="table-seat-label">
        {seat.name}
        {seat.bot && <span className="table-bot"> (bot)</span>}
        <span className="table-count"> · {cards} kort</span>
      </div>
      <div className="table-backs" aria-hidden="true">
        {Array.from({ length: cards }, (_, index) => (
          <CardBack key={index} size="xs" />
        ))}
      </div>
    </div>
  )
}

function Trick({ plays, positionOf, faded }: { plays: TrickPlay[]; positionOf: (seat: SeatIndex) => Position; faded: boolean }) {
  return (
    <div className={`table-trick${faded ? " is-faded" : ""}`} role="group" aria-label={faded ? "Sidste stik" : "Stikket"}>
      {plays.map((play) => (
        <div key={play.seat} className={`table-trick-slot table-slot-${positionOf(play.seat)}`}>
          <Card {...parseCardCode(play.card)} />
        </div>
      ))}
    </div>
  )
}

function RoundPoints({ seats, points, moonShooter }: { seats: SeatInfo[]; points: number[]; moonShooter: SeatIndex | null }) {
  return (
    <div className="table-result">
      <h2>Point i runden</h2>
      {moonShooter !== null && <p>{seats[moonShooter]?.name} tog alle point!</p>}
      <table>
        <tbody>
          {seats.map((seat) => (
            <tr key={seat.seat}>
              <th scope="row">{seat.name}</th>
              <td>{points[seat.seat] ?? 0}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p>
        <a href="/">Tilbage til lobbyen</a>
      </p>
    </div>
  )
}
