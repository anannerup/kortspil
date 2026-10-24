import { useEffect, useRef, useState } from "react"
import { LayoutGroup, MotionConfig } from "motion/react"
import { CardBack, type CardCode, type Suit } from "~/cards"
import { Hand, PASS_SIZE } from "./Hand"
import type { SeatIndex, ServerMessage, TableState, TrickPlay } from "./messages"
import { PassCentre } from "./PassCentre"
import { GameOver, MoonChoice, RundeResult, ScoreSheet } from "./ScoreSheet"
import { SidePanel } from "./SidePanel"
import { playAgainWait, statusText } from "./status"
import { POSITIONS, Trick, type Position } from "./Trick"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { REJECTIONS, pointsLabel } from "./texts"
import { useTableChat } from "./useTableChat"
import { secondsLeft, useNow } from "./turnTimer"
import { formatClock } from "~/app/countdown"
import "./table.css"

const LOBBY_PATH = "/"

/**
 * The live table, laid out like the bridge app on iPad: green felt with the
 * stik in a framed square and the players' name tags on its edges, the
 * opponents' hands as stacks at the edges of the felt, your hand as a fan
 * at the bottom, and a white panel beside it (under it on narrow screens).
 * New chat messages show briefly as a speech bubble at the author's tag.
 *
 * It renders the state the server sends and sends intents; no rules are
 * decided here. Animations are presentational (Motion): cards glide between
 * hand, pass slots and stik, and never hold back the state shown.
 *
 * The turn timer (tickets 18 and 19) shows on the name tags: a bar that
 * runs down on each seat the server has a clock for, red from the warning,
 * a grey tag with a countdown for a frakoblet player, and "Bot (overtog fra
 * …)" once a bot took a seat over.
 */
export function TablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  // The state shown and when it arrived (performance.now()), for the clocks.
  const [shown, setShown] = useState<{ state: TableState; at: number } | null>(null)
  const state = shown?.state ?? null
  const [warning, setWarning] = useState<string | null>(null)
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
  const chat = useTableChat(userId, (text) => subscription.current?.send("chat", { text }))
  const receiveChat = chat.receive

  useEffect(() => {
    const handle = (message: ServerMessage) => {
      if (receiveChat(message)) return
      if (message.type === "closed") {
        window.location.assign(LOBBY_PATH)
        return
      }
      if (message.type === "forladt" || message.type === "waiting") {
        // The server decides what this bord's URL shows now: the waiting
        // page, or the lobby with why you can't come back.
        window.location.reload()
        return
      }
      if (message.type === "turn_warning") {
        setWarning(`Din tur — ${Math.round(message.seconds_left)} sekunder tilbage`)
        return
      }
      if (message.type === "rejected") {
        setNotice(REJECTIONS[message.reason] ?? "Trækket blev afvist.")
        setPlayedCard(null)
        return
      }
      if (message.type !== "state") return
      setNotice(null)
      setShown((current) => (current && isNewer(current.state, message.state) ? current : { state: message.state, at: performance.now() }))
    }
    subscription.current = subscribeToTable(tableId, {
      onMessage: handle,
      onConnectionChange: setConnected,
      onRejected: () => setRefused(true),
    })
    return () => subscription.current?.close()
  }, [tableId, receiveChat])

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

  // The warning lasts until something happens in the spil (you act).
  const version = state?.version
  useEffect(() => setWarning(null), [version])

  const now = useNow(state !== null && state.seats.some((seat) => seat.seconds_left !== null))

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
  const playAgain = playAgainWait(state, nameOf)

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
        ? playAgain.asked
          ? null
          : { label: "Spil igen", onClick: () => subscription.current?.send("play_again", {}) }
        : { label: "Næste runde", onClick: () => subscription.current?.send("next_runde", {}) }
  const leftFor = (seat: SeatIndex | null) => (seat === null ? null : secondsLeft(seats[seat], shown?.at ?? 0, now))
  const warnFrom = state.timer.limit - state.timer.warning
  const waitedFor = view.to_act !== null && view.to_act !== me ? view.to_act : null
  const waitedLeft = leftFor(waitedFor)
  const status =
    myTurn && pickedSuit
      ? "Vælg kortet, eller tryk Fortryd."
      : finished && playAgain.note
        ? playAgain.note
      : waitedLeft !== null && (seats[waitedFor ?? 0]?.frakoblet || waitedLeft <= warnFrom)
        ? `Venter på ${nameOf(waitedFor)}… ${formatClock(waitedLeft)}`
        : statusText(state, nameOf)

  const tag = (seat: SeatIndex | undefined, edge: Position) => {
    if (seat === undefined) return null
    const info = seats[seat]
    const left = leftFor(seat)
    const away = info?.frakoblet ?? false
    const classes = [
      "table-tag",
      `table-tag-${edge}`,
      view.to_act === seat ? "is-active" : "",
      away ? "is-away" : "",
      left !== null && left <= warnFrom ? "is-warning" : "",
    ]
    const said = chat.bubbles.get(seat)
    return (
      <>
        <span className={classes.filter(Boolean).join(" ")}>
          {seat === me ? "Dig" : info?.took_over_from ? `Bot (overtog fra ${info.took_over_from})` : nameOf(seat)}
          {seat !== me && info?.bot && !info.took_over_from && <span className="table-tag-bot"> · bot</span>}
          {away && left !== null && <span className="table-tag-away"> · frakoblet {formatClock(left)}</span>}
          {left !== null && (
            <span className="table-tag-timer" aria-hidden="true" style={{ transform: `scaleX(${left / state.timer.limit})` }} />
          )}
        </span>
        {said && (
          <span key={said.id} className={`table-bubble table-bubble-${edge}`} aria-hidden="true">
            {said.text}
          </span>
        )}
      </>
    )
  }
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
            {warning && (
              <p className="table-toast table-toast-warning" role="alert">
                {warning}
              </p>
            )}

            {view.phase === "choosing_moon" && (
              <div className="table-overlay-host">
                <MoonChoice state={state} onChoose={(option) => subscription.current?.send("choose_moon", { option })} />
              </div>
            )}
            {view.phase === "complete" && (
              <div className="table-overlay-host">
                {finished ? (
                  <GameOver state={state} playAgain={playAgain} onPlayAgain={() => subscription.current?.send("play_again", {})} onLeave={leave} />
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
            chat={chat}
            userId={userId}
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
