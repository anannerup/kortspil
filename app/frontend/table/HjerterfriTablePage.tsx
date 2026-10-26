import { useCallback, useEffect, useRef, useState } from "react"
import { MotionConfig } from "motion/react"
import type { CardCode, Suit } from "~/cards"
import { Hand, PASS_SIZE } from "./Hand"
import type { HjerterfriTableState, SeatIndex } from "./messages"
import { PassCentre } from "./PassCentre"
import { PassFlights } from "./CardAnimations"
import { receiverOf } from "./passing"
import { GameOver, MoonChoice, RundeResult, ScoreSheet } from "./ScoreSheet"
import { SidePanel } from "./SidePanel"
import { statusText } from "./status"
import { Trick, type Position } from "./Trick"
import { framesFor } from "./timeline"
import { useTimeline } from "./useTimeline"
import { pointsLabel } from "./texts"
import { SeatTag, StatusLine } from "./SeatTag"
import { LeaveForm, OpponentStack, TableToasts, useTableShell, useTrickAnchors } from "./shell"
import "./table.css"

/**
 * The hjerterfri table, laid out like the bridge app on iPad: green felt with the
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
 * a grey tag with a countdown for a frakoblet player, each bot's level, and
 * "Bot · Let (overtog fra …)" once a bot took a seat over.
 *
 * The subscription, the panel's frame, the toasts and leaving are the
 * table shell's (./shell), the same as at es-makker; the hand with its
 * suit pick, the bytte, the timeline and the overlays are hjerterfri's.
 */
export function HjerterfriTablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  // The frame on screen: the timeline paces the server's states.
  const [shown, push] = useTimeline(framesFor)
  const frame = shown?.frame ?? null
  const state = frame?.state ?? null
  const [passSelection, setPassSelection] = useState<CardCode[]>([])
  const [pickedSuit, setPickedSuit] = useState<Suit | null>(null)
  const [playedCard, setPlayedCard] = useState<CardCode | null>(null)
  const [showScore, setShowScore] = useState(false)
  const shell = useTableShell<HjerterfriTableState>({ tableId, userId, onState: push, onRejected: () => setPlayedCard(null) })
  const { chat, send } = shell
  // Where cards fly from and sweep to: the opponents' stacks and your hand,
  // and the rect your played card had when you tapped it.
  const me = state?.view.seat ?? 0
  const { seats: seatEls, playedFrom, positionOf, seatRect, flightSource } = useTrickAnchors(me)
  // Where a card was when it was tapped in the pass: hand to slot and back.
  const passFrom = useRef(new Map<CardCode, DOMRect>())

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
    send("play", { card })
  }, [playedFrom, send])
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

  // A new runde or spil starts with nothing chosen.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setPassSelection([])
    playedFrom.current.clear()
    passFrom.current.clear()
  }, [rundeKey, playedFrom])

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

  if (shell.refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state || !frame) return <p className="table-loading">Henter bordet…</p>

  const { view, seats, score } = state
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const finished = state.status === "finished"
  // After the spil, everyone sits at the new bord in the lobby: leaving is standing up from it.
  const next = finished ? (state.next_path ?? null) : null
  const goNext = () => next && window.location.assign(next)

  const pass = () => send("pass", { cards: passSelection })
  const leave = shell.leave
  const primary =
    view.phase !== "complete"
      ? null
      : finished
        ? next
          ? { label: "Til bordet", onClick: goNext }
          : null
        : { label: "Næste runde", onClick: () => send("next_runde", {}) }
  const receivedAt = shown?.at ?? 0
  const status = (
    <StatusLine
      state={state}
      receivedAt={receivedAt}
      text={myTurn && pickedSuit ? "Vælg kortet, eller tryk Fortryd." : statusText(state, nameOf)}
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
        marker={view.phase === "passing" && view.pass_direction !== "none" ? (view.passed_seats.includes(seat) ? "is-passed" : "is-choosing") : null}
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

            <TableToasts notice={shell.notice} warning={shell.warning} />

            {view.phase === "choosing_moon" && (
              <div className="table-overlay-host">
                <MoonChoice state={state} onChoose={(option) => send("choose_moon", { option })} />
              </div>
            )}
            {view.phase === "complete" && (
              <div className="table-overlay-host">
                {finished ? (
                  <GameOver state={state} onNext={goNext} onLeave={leave} />
                ) : (
                  <RundeResult state={state} onNext={() => send("next_runde", {})} />
                )}
              </div>
            )}
          </div>

          <SidePanel
            state={state}
            title={state.table_kind === "practice" ? "Øvebord" : `Bord ${state.table_id}`}
            connected={shell.connected}
            status={status}
            positionOf={positionOf}
            primary={primary}
            onShowScore={() => setShowScore(true)}
            onLeave={leave}
            chat={chat}
            userId={userId}
            lastTrick={frame.lastTrick}
          />

          <LeaveForm formRef={shell.leaveForm} next={next} departurePath={departurePath} />
          {showScore && <ScoreSheet seats={seats} score={score} rules={state.rules} onClose={() => setShowScore(false)} />}
        </section>
    </MotionConfig>
  )
}
