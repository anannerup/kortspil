import { memo, useCallback, useEffect, useRef, useState } from "react"
import { MotionConfig } from "motion/react"
import { CardBack, type CardCode, type Suit } from "~/cards"
import { Hand, PASS_SIZE } from "./Hand"
import type { SeatIndex, ServerMessage, TableState, TrickPlay } from "./messages"
import { PassCentre } from "./PassCentre"
import { PassFlights } from "./PassFlights"
import { receiverOf } from "./passing"
import { GameOver, MoonChoice, RundeResult, ScoreSheet } from "./ScoreSheet"
import { SidePanel } from "./SidePanel"
import { playAgainWait, statusText } from "./status"
import { POSITIONS, Trick, type Position } from "./Trick"
import { useTimeline } from "./useTimeline"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { REJECTIONS, pointsLabel } from "./texts"
import { useTableChat } from "./useTableChat"
import { SeatTag, StatusLine } from "./SeatTag"
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
 * hand, pass slots and stik. The server's states are played back as frames
 * at the pace of those animations (timeline.ts), since bots answer at once.
 *
 * The turn timer (tickets 18 and 19) shows on the name tags: a bar that
 * runs down on each seat the server has a clock for, red from the warning,
 * a grey tag with a countdown for a frakoblet player, and "Bot (overtog fra
 * …)" once a bot took a seat over.
 */
export function TablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  // The frame on screen: the timeline paces the server's states.
  const [shown, push] = useTimeline()
  const frame = shown?.frame ?? null
  const state = frame?.state ?? null
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
  // Where a card was when it was tapped in the pass: hand to slot and back.
  const passFrom = useRef(new Map<CardCode, DOMRect>())
  const chat = useTableChat(userId, useCallback((text: string) => subscription.current?.send("chat", { text }), []))
  const receiveChat = chat.receive

  // Stable, so the memoised hand only renders when what it shows changes.
  const togglePass = useCallback((code: CardCode, from: DOMRect | null) => {
    if (from) passFrom.current.set(code, from)
    setPassSelection((current) =>
      current.includes(code) ? current.filter((card) => card !== code) : current.length < PASS_SIZE ? [...current, code] : current,
    )
  }, [])
  const play = useCallback((card: CardCode, from: DOMRect | null) => {
    if (from) playedFrom.current.set(card, from)
    setPlayedCard(card)
    setPickedSuit(null)
    subscription.current?.send("play", { card })
  }, [])
  const passSource = useCallback((code: CardCode) => {
    const rect = passFrom.current.get(code)
    return rect ? { rect } : null
  }, [])
  // The pile in front of a seat, where the pass lands: a card's size, a
  // little over halfway from the middle of the table to the seat's hand.
  const frameEl = useRef<HTMLDivElement | null>(null)
  const pileRect = useCallback(
    (seat: SeatIndex) => {
      const middle = frameEl.current?.getBoundingClientRect()
      const hand = seatEls.get(seat)?.getBoundingClientRect()
      if (!middle || !hand) return null
      const width = Math.max(40, middle.width * 0.13)
      const x = middle.left + middle.width / 2 + (hand.left + hand.width / 2 - (middle.left + middle.width / 2)) * 0.55
      const y = middle.top + middle.height / 2 + (hand.top + hand.height / 2 - (middle.top + middle.height / 2)) * 0.55
      return new DOMRect(x - width / 2, y - width * 0.715, width, width * 1.43)
    },
    [seatEls],
  )
  // A card you were passed flies into your hand from your pile.
  const received = useRef<{ cards: CardCode[]; me: SeatIndex }>({ cards: [], me: 0 })
  const handSource = useCallback(
    (code: CardCode) => {
      const back = passSource(code)
      if (back) return back
      if (!received.current.cards.includes(code)) return null
      const rect = pileRect(received.current.me)
      return rect ? { rect } : null
    },
    [passSource, pileRect],
  )

  useEffect(() => {
    const handle = (message: ServerMessage) => {
      if (receiveChat(message)) return
      if (message.type === "closed") {
        window.location.assign(LOBBY_PATH)
        return
      }
      if (message.type === "waiting") {
        // The bord for the next spil waits in the lobby, at its own URL.
        window.location.assign(message.path)
        return
      }
      if (message.type === "forladt") {
        // The server decides what this bord's URL shows now: the lobby
        // with why you can't come back.
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
      push(message.state)
    }
    subscription.current = subscribeToTable(tableId, {
      onMessage: handle,
      onConnectionChange: setConnected,
      onRejected: () => setRefused(true),
    })
    return () => subscription.current?.close()
  }, [tableId, receiveChat, push])

  // A new runde or spil starts with nothing chosen.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setPassSelection([])
    playedFrom.current.clear()
    passFrom.current.clear()
  }, [rundeKey])

  // The suit picker only lives during your turn.
  const myTurn = state !== null && state.view.phase === "playing" && state.view.to_act === state.view.seat
  useEffect(() => {
    if (!myTurn) setPickedSuit(null)
  }, [myTurn])

  // Only right after the pass do received cards fly in (not on a reload).
  const shownPhase = useRef<string | null>(null)
  if (state && shownPhase.current !== state.view.phase) {
    const passDone = shownPhase.current === "passing"
    received.current = passDone ? { cards: state.view.received_cards, me: state.view.seat } : { cards: [], me: 0 }
    shownPhase.current = state.view.phase
  }

  // The played card has left the hand once the state says so; forget it then
  // (it is kept until that render, so the card leaves at once, not fading).
  const handNow = state?.view.hand
  useEffect(() => {
    if (playedCard && handNow && !handNow.includes(playedCard)) setPlayedCard(null)
  }, [playedCard, handNow])

  // The warning lasts until something happens in the spil (you act).
  const version = state?.version
  useEffect(() => setWarning(null), [version])

  // Notices fade after a while.
  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(null), 3500)
    return () => clearTimeout(timer)
  }, [notice])

  // Stable per seat, so the memoised stik only renders when its frame changes.
  const me = state?.view.seat ?? 0
  const positionOf = useCallback((seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south", [me])
  const seatRect = useCallback((seat: SeatIndex) => seatEls.get(seat)?.getBoundingClientRect() ?? null, [seatEls])
  const flightSource = useCallback(
    (trickPlay: TrickPlay) => {
      const own = trickPlay.seat === me ? playedFrom.current.get(trickPlay.card) : undefined
      if (own) return { rect: own }
      const rect = seatRect(trickPlay.seat)
      return rect ? { rect, scale: 0.45 } : null
    },
    [me, seatRect],
  )

  if (refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state || !frame) return <p className="table-loading">Henter bordet…</p>

  const { view, seats, score } = state
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const finished = state.status === "finished"
  const playAgain = playAgainWait(state, nameOf)

  const pass = () => subscription.current?.send("pass", { cards: passSelection })
  const leave = () => leaveForm.current?.requestSubmit()
  const primary =
    view.phase !== "complete"
      ? null
      : finished
        ? playAgain.asked
          ? null
          : { label: "Spil igen", onClick: () => subscription.current?.send("play_again", {}) }
        : { label: "Næste runde", onClick: () => subscription.current?.send("next_runde", {}) }
  const receivedAt = shown?.at ?? 0
  const status = (
    <StatusLine
      state={state}
      receivedAt={receivedAt}
      text={myTurn && pickedSuit ? "Vælg kortet, eller tryk Fortryd." : finished && playAgain.note ? playAgain.note : statusText(state, nameOf)}
      nameOf={nameOf}
    />
  )
  const tag = (seat: SeatIndex | undefined, edge: Position) =>
    seat === undefined ? null : (
      <SeatTag
        info={seats[seat]}
        edge={edge}
        label={seat === me ? "Dig" : nameOf(seat)}
        isMe={seat === me}
        active={view.to_act === seat}
        pass={view.phase === "passing" && view.pass_direction !== "none" ? (view.passed_seats.includes(seat) ? "passed" : "choosing") : null}
        receivedAt={receivedAt}
        timer={state.timer}
        said={chat.bubbles.get(seat)}
      />
    )
  const opponent = (position: Exclude<Position, "south">) => {
    const seat = seatAt(position)
    if (!seat) return null
    const count = view.card_counts[String(seat.seat)] ?? 0
    return <OpponentStack anchor={seatEls.ref(seat.seat)} position={position} name={seat.name} count={count} />
  }

  return (
    <MotionConfig reducedMotion="user">
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

            <div ref={frameEl} className="table-frame">
              {tag(seatAt("north")?.seat, "north")}
              {tag(seatAt("west")?.seat, "west")}
              {tag(seatAt("east")?.seat, "east")}
              {tag(me, "south")}
              {view.phase === "passing" ? (
                <PassCentre
                  view={view}
                  seats={seats}
                  selection={passSelection}
                  onToggle={togglePass}
                  onPass={pass}
                  from={passSource}
                  giveTo={frame.pass === "give" ? () => pileRect(receiverOf(me, view.pass_direction)) : null}
                />
              ) : (
                <Trick plays={frame.trick} sweepTo={frame.sweepTo} positionOf={positionOf} source={flightSource} seatRect={seatRect} />
              )}
              <span className="table-corner table-corner-left">{view.hearts_broken ? "♥ brudt" : "♥ ikke brudt"}</span>
              <span className="table-corner table-corner-right">{pointsLabel(state.points_taken[me] ?? 0)}</span>
            </div>

            {frame.pass && (
              <PassFlights
                key={`${state.game_id}:${state.round_number}:${frame.pass}`}
                stage={frame.pass}
                me={me}
                direction={view.pass_direction}
                ownPass={view.own_pass}
                seatRect={seatRect}
                pileRect={pileRect}
              />
            )}

            <div ref={seatEls.ref(me)} className="table-hand-row">
              <Hand
                view={view}
                pickedSuit={pickedSuit}
                onPickSuit={setPickedSuit}
                onPlay={play}
                passSelection={passSelection}
                onTogglePass={togglePass}
                playedCard={playedCard}
                returningFrom={handSource}
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
            lastTrick={frame.lastTrick}
          />

          <form ref={leaveForm} method="post" action={departurePath} hidden>
            <input type="hidden" name="authenticity_token" value={csrfToken()} />
          </form>
          {showScore && <ScoreSheet seats={seats} score={score} rules={state.rules} onClose={() => setShowScore(false)} />}
        </section>
    </MotionConfig>
  )
}

/** An opponent's hand: card backs at the edge of the felt. Renders only when the count changes. */
const OpponentStack = memo(function OpponentStack(props: {
  anchor: (element: HTMLElement | null) => void
  position: Exclude<Position, "south">
  name: string
  count: number
}) {
  const { anchor, position, name, count } = props
  return (
    <div ref={anchor} className={`table-stack table-stack-${position}`} aria-label={`${name}: ${count} kort`}>
      {Array.from({ length: count }, (_, index) => (
        <CardBack key={index} size="sm" />
      ))}
    </div>
  )
})

/**
 * Elements by key, for measuring where a card flies from or to. The ref
 * callbacks are stable per key, so React never detaches them on re-render,
 * and the object itself is stable too.
 */
function useAnchors<K>() {
  const [anchors] = useState(() => {
    const elements = new Map<K, HTMLElement>()
    const refs = new Map<K, (element: HTMLElement | null) => void>()
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
  })
  return anchors
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}
