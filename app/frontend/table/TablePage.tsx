import { useEffect, useRef, useState } from "react"
import { LayoutGroup, MotionConfig } from "motion/react"
import { CardBack, type CardCode, type Suit } from "~/cards"
import { Hand, PASS_SIZE } from "./Hand"
import type { SeatIndex, ServerMessage, TableState, TrickPlay } from "./messages"
import { PassCentre } from "./PassCentre"
import { GameOver, MoonChoice, RundeResult, ScoreSheet } from "./ScoreSheet"
import { SidePanel } from "./SidePanel"
import { statusText } from "./status"
import { POSITIONS, Trick, type Position } from "./Trick"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { REJECTIONS, pointsLabel } from "./texts"
import "./table.css"

const LOBBY_PATH = "/"

/**
 * The live table, laid out like the bridge app on iPad: green felt with the
 * stik in a framed square and the players' name tags on its edges, the
 * opponents' hands as stacks at the edges of the felt, your hand as a fan
 * at the bottom, and a white panel beside it (under it on narrow screens).
 *
 * It renders the state the server sends and sends intents; no rules are
 * decided here. Animations are presentational (Motion): cards glide between
 * hand, pass slots and stik, and never hold back the state shown.
 */
export function TablePage({ tableId, departurePath }: { tableId: number; departurePath: string }) {
  const [state, setState] = useState<TableState | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [passSelection, setPassSelection] = useState<CardCode[]>([])
  const [pickedSuit, setPickedSuit] = useState<Suit | null>(null)
  const [playedCard, setPlayedCard] = useState<CardCode | null>(null)
  const [showScore, setShowScore] = useState(false)
  const subscription = useRef<TableSubscription | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)
  // Where cards fly from and sweep to: the opponents' stacks and your hand,
  // and the rect your played card had when you tapped it.
  const seatEls = useAnchors<SeatIndex>()
  const playedFrom = useRef(new Map<CardCode, DOMRect>())

  useEffect(() => {
    const handle = (message: ServerMessage) => {
      if (message.type === "closed") {
        window.location.assign(LOBBY_PATH)
        return
      }
      if (message.type === "rejected") {
        setNotice(REJECTIONS[message.reason] ?? "Trækket blev afvist.")
        setPlayedCard(null)
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

  // A new runde or spil starts with nothing chosen.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setPassSelection([])
    playedFrom.current.clear()
  }, [rundeKey])

  // The suit picker only lives during your turn.
  const myTurn = state !== null && state.view.phase === "playing" && state.view.to_act === state.view.seat
  useEffect(() => {
    if (!myTurn) setPickedSuit(null)
  }, [myTurn])

  // Notices fade after a while.
  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(null), 3500)
    return () => clearTimeout(timer)
  }, [notice])

  if (refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state) return <p className="table-loading">Henter bordet…</p>

  const { view, seats, score } = state
  const me = view.seat
  const positionOf = (seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south"
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const finished = state.status === "finished"

  const togglePass = (code: CardCode) =>
    setPassSelection((current) =>
      current.includes(code) ? current.filter((card) => card !== code) : current.length < PASS_SIZE ? [...current, code] : current,
    )
  const pass = () => subscription.current?.send("pass", { cards: passSelection })
  const play = (card: CardCode, from: DOMRect | null) => {
    if (from) playedFrom.current.set(card, from)
    setPlayedCard(card)
    setPickedSuit(null)
    subscription.current?.send("play", { card })
  }
  const leave = () => leaveForm.current?.requestSubmit()
  const seatRect = (seat: SeatIndex) => seatEls.get(seat)?.getBoundingClientRect() ?? null
  const flightSource = (trickPlay: TrickPlay) => {
    const own = trickPlay.seat === me ? playedFrom.current.get(trickPlay.card) : undefined
    if (own) return { rect: own, scale: 1 }
    const rect = seatRect(trickPlay.seat)
    return rect ? { rect, scale: 0.45 } : null
  }
  const primary =
    view.phase !== "complete"
      ? null
      : finished
        ? { label: "Spil igen", onClick: () => subscription.current?.send("play_again", {}) }
        : { label: "Næste runde", onClick: () => subscription.current?.send("next_runde", {}) }
  const status = myTurn && pickedSuit ? "Vælg kortet, eller tryk Fortryd." : statusText(state, nameOf)

  const tag = (seat: SeatIndex | undefined, edge: Position) =>
    seat === undefined ? null : (
      <span className={`table-tag table-tag-${edge}${view.to_act === seat ? " is-active" : ""}`}>
        {seat === me ? "Dig" : nameOf(seat)}
        {seat !== me && seats[seat]?.bot && <span className="table-tag-bot"> · bot</span>}
      </span>
    )
  const opponent = (position: Exclude<Position, "south">) => {
    const seat = seatAt(position)
    if (!seat) return null
    const count = view.card_counts[String(seat.seat)] ?? 0
    return (
      <div ref={seatEls.ref(seat.seat)} className={`table-stack table-stack-${position}`} aria-label={`${seat.name}: ${count} kort`}>
        {Array.from({ length: count }, (_, index) => (
          <CardBack key={index} size="sm" />
        ))}
      </div>
    )
  }

  return (
    <MotionConfig reducedMotion="user">
      <LayoutGroup>
        <section className="table-page" aria-label={`Bord ${state.table_id}`}>
          <div
            className="table-felt"
            onClick={(event) => {
              if (pickedSuit && !(event.target as HTMLElement).closest("button")) setPickedSuit(null)
            }}
          >
            {opponent("north")}
            {opponent("west")}
            {opponent("east")}

            <div className="table-frame">
              {tag(seatAt("north")?.seat, "north")}
              {tag(seatAt("west")?.seat, "west")}
              {tag(seatAt("east")?.seat, "east")}
              {tag(me, "south")}
              {view.phase === "passing" ? (
                <PassCentre view={view} seats={seats} selection={passSelection} onToggle={togglePass} onPass={pass} />
              ) : (
                <Trick view={view} positionOf={positionOf} source={flightSource} seatRect={seatRect} />
              )}
              <span className="table-corner table-corner-left">{view.hearts_broken ? "♥ brudt" : "♥ ikke brudt"}</span>
              <span className="table-corner table-corner-right">{pointsLabel(state.points_taken[me] ?? 0)}</span>
            </div>

            <div ref={seatEls.ref(me)} className="table-hand-row">
              <Hand
                view={view}
                pickedSuit={pickedSuit}
                onPickSuit={setPickedSuit}
                onPlay={play}
                passSelection={passSelection}
                onTogglePass={togglePass}
                playedCard={playedCard}
              />
            </div>

            <button type="button" className={`table-undo${pickedSuit ? " is-on" : ""}`} disabled={!pickedSuit} onClick={() => setPickedSuit(null)}>
              ↩ Fortryd
            </button>

            <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
              {notice}
            </p>

            {view.phase === "choosing_moon" && (
              <div className="table-overlay-host">
                <MoonChoice state={state} onChoose={(option) => subscription.current?.send("choose_moon", { option })} />
              </div>
            )}
            {view.phase === "complete" && (
              <div className="table-overlay-host">
                {finished ? (
                  <GameOver state={state} onPlayAgain={() => subscription.current?.send("play_again", {})} onLeave={leave} />
                ) : (
                  <RundeResult state={state} onNext={() => subscription.current?.send("next_runde", {})} />
                )}
              </div>
            )}
          </div>

          <SidePanel
            state={state}
            title={state.table_kind === "practice" ? "Øvebord" : `Bord ${state.table_id}`}
            connected={connected}
            status={status}
            positionOf={positionOf}
            primary={primary}
            onShowScore={() => setShowScore(true)}
            onLeave={leave}
          />

          <form ref={leaveForm} method="post" action={departurePath} hidden>
            <input type="hidden" name="authenticity_token" value={csrfToken()} />
          </form>
          {showScore && <ScoreSheet seats={seats} score={score} rules={state.rules} onClose={() => setShowScore(false)} />}
        </section>
      </LayoutGroup>
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
