// PROTOTYPE (throwaway): three layouts of the hjerterfri table, inspired by a
// bridge app on iPad (video IMG_2459). Switch with ?variant=A|B|C on
// /tables/:id. They render the same server state as TablePage and send the
// same intents. Delete once a direction is chosen.
//
// Taken from the video, in every variant:
// - Playing takes two taps. The first tap on the hand picks a suit: the fan
//   goes away and that suit's cards come out big just under the trick. The
//   second tap plays one of them, and it flies into the stik. "Fortryd" (or a
//   tap on the felt) puts the fan back.
// - The pass happens in the middle: chosen cards leave the fan for three
//   slots on the table, with the direction and the button right there.
// - The active player's name tag lights up; the stik flies in and sweeps to
//   the winner (the real Trick component); the hand is a fan.
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react"
import { Card, CardBack, parseCardCode, type CardCode, type Suit } from "~/cards"
import type { MoonChoiceOption, SeatIndex, TableState, TrickPlay } from "../messages"
import { GameOver, MoonChoice, RundeResult } from "../ScoreSheet"
import { statusText } from "../status"
import { DIRECTION_LABELS, PASS_INSTRUCTIONS, joinNames, pointsLabel, rulesSummary } from "../texts"
import { POSITIONS, Trick, type Position } from "../Trick"
import "./prototype.css"

export interface ProtoTableProps {
  state: TableState
  notice: string | null
  connected: boolean
  selected: CardCode[]
  toggle: (code: CardCode) => void
  pass: () => void
  play: (card: CardCode) => void
  nextRunde: () => void
  playAgain: () => void
  chooseMoon: (option: MoonChoiceOption) => void
  /** Submits "Forlad bordet" (forfeits a spil in progress). */
  leaveNow: () => void
}

export const PROTOTYPE_VARIANTS = [
  { key: "A", name: "Bridge: filt + fast sidepanel" },
  { key: "B", name: "Stor hånd: touch først, handlingsbjælke" },
  { key: "C", name: "Overblik: stillingen altid fremme" },
]

const PASS_SIZE = 3
const suitOf = (code: CardCode) => parseCardCode(code).suit

function derive(props: ProtoTableProps) {
  const { state } = props
  const { view, seats } = state
  const me = view.seat
  const positionOf = (seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south"
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex | null) => (seat === null ? "" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const passing = view.phase === "passing"
  const passed = view.passed_seats.includes(me)
  const choosing = passing && !passed
  const myTurn = view.to_act === me && view.phase === "playing"
  const finished = state.status === "finished"
  return { view, seats, me, positionOf, seatAt, nameOf, passing, passed, choosing, myTurn, finished }
}

/**
 * The play state shared by a variant's hand, centre and buttons: the suit
 * picked with the first tap, and where each played card was when tapped
 * (so it flies from there).
 */
function usePlayFlow(props: ProtoTableProps) {
  const { myTurn } = derive(props)
  const [suit, setSuit] = useState<Suit | null>(null)
  const playedFrom = useRef(new Map<CardCode, DOMRect>())
  useEffect(() => {
    if (!myTurn) setSuit(null)
  }, [myTurn])
  const play = (code: CardCode, element: HTMLElement | null) => {
    const rect = element?.getBoundingClientRect()
    if (rect) playedFrom.current.set(code, rect)
    setSuit(null)
    props.play(code)
  }
  return { suit, pick: setSuit, cancel: () => setSuit(null), play, playedFrom }
}
type PlayFlow = ReturnType<typeof usePlayFlow>

/** Where cards fly from and sweep to: elements marked data-proto-seat. */
const anchorRect = (seat: SeatIndex) => document.querySelector(`[data-proto-seat="${seat}"]`)?.getBoundingClientRect() ?? null

/** The real stik, with its flights and sweep, sized by the variant's CSS. */
function AnimatedTrick({ props, flow }: { props: ProtoTableProps; flow: PlayFlow }) {
  const { view, positionOf, me } = derive(props)
  const source = (trickPlay: TrickPlay) => {
    const own = trickPlay.seat === me ? flow.playedFrom.current.get(trickPlay.card) : undefined
    if (own) return { rect: own, scale: 1 }
    const rect = anchorRect(trickPlay.seat)
    return rect ? { rect, scale: 0.45 } : null
  }
  return (
    <div className="proto-trick">
      <Trick view={view} positionOf={positionOf} source={source} seatRect={anchorRect} />
    </div>
  )
}

/**
 * The hand. In play: a fan; the first tap picks a suit and swaps the fan for
 * that suit's cards, big; the second tap plays. In the pass: a tap moves the
 * card to the middle (PassCentre) and out of the fan.
 */
function PlayHand({ props, flow }: { props: ProtoTableProps; flow: PlayFlow }) {
  const { state, selected, toggle } = props
  const { view, me, choosing, passing, myTurn } = derive(props)
  const legal = new Set(view.legal_moves)
  const received = new Set(view.received_cards)
  const key = `${state.game_id}:${state.round_number}`

  if (myTurn && flow.suit) {
    const cards = view.hand.filter((code) => suitOf(code) === flow.suit)
    return (
      <div className="proto-staged" data-proto-seat={me} key={key}>
        {cards.map((code) => (
          <StagedCard key={code} code={code} legal={legal.has(code)} onPlay={flow.play} />
        ))}
      </div>
    )
  }

  const shown = choosing ? view.hand.filter((code) => !selected.includes(code)) : passing ? view.hand.filter((code) => !view.own_pass.includes(code)) : view.hand
  const mid = (shown.length - 1) / 2
  return (
    <div className={`proto-fan${myTurn ? " is-turn" : ""}`} data-proto-seat={me} key={key}>
      {shown.map((code, index) => {
        const offset = index - mid
        const style = { "--rot": `${offset * 3.2}deg`, "--lift": `${offset * offset * 1.1}px` } as CSSProperties
        const onClick = choosing ? () => toggle(code) : myTurn ? () => flow.pick(suitOf(code)) : undefined
        const full = choosing && selected.length >= PASS_SIZE
        return (
          <div key={code} className="proto-fan-card" style={style}>
            <Card
              {...parseCardCode(code)}
              state={onClick && !full ? "playable" : "idle"}
              isNew={received.has(code)}
              onClick={full ? undefined : onClick}
            />
          </div>
        )
      })}
    </div>
  )
}

function StagedCard({ code, legal, onPlay }: { code: CardCode; legal: boolean; onPlay: (code: CardCode, element: HTMLElement | null) => void }) {
  const ref = useRef<HTMLDivElement>(null)
  return (
    <div ref={ref} className="proto-staged-card">
      <Card {...parseCardCode(code)} state={legal ? "playable" : "disabled"} onClick={legal ? () => onPlay(code, ref.current) : undefined} />
    </div>
  )
}

/** The pass, in the middle of the table: three slots, the direction, the button. */
function PassCentre({ props }: { props: ProtoTableProps }) {
  const { state, selected, toggle, pass } = props
  const { view, seats, me, nameOf, passed } = derive(props)
  const offset = { left: 1, right: 3, across: 2, none: 0 }[view.pass_direction]
  const receiver = (me + offset) % 4
  const cards = passed ? view.own_pass : selected
  const waiting = seats.filter((seat) => !view.passed_seats.includes(seat.seat)).map((seat) => seat.name)
  return (
    <div className="proto-pass">
      <strong className="proto-pass-title">
        {PASS_INSTRUCTIONS[view.pass_direction]} · {nameOf(receiver)}
      </strong>
      <div className="proto-pass-slots">
        {Array.from({ length: PASS_SIZE }, (_, index) => {
          const code = cards[index]
          return (
            <div key={index} className="proto-pass-slot">
              {code && <Card {...parseCardCode(code)} state={passed ? "idle" : "playable"} onClick={passed ? undefined : () => toggle(code)} />}
            </div>
          )
        })}
      </div>
      {passed ? (
        <span className="proto-pass-wait">{waiting.length > 0 ? `Venter på ${joinNames(waiting)}…` : "Kortene byttes…"}</span>
      ) : (
        <button type="button" className="proto-btn proto-btn-primary proto-btn-xl" disabled={selected.length !== PASS_SIZE} onClick={pass}>
          {selected.length === PASS_SIZE ? "Giv kortene" : `Vælg ${PASS_SIZE - selected.length} kort mere`}
        </button>
      )}
    </div>
  )
}

/** The middle of the felt: the pass, or the stik. */
function Centre({ props, flow }: { props: ProtoTableProps; flow: PlayFlow }) {
  const { passing } = derive(props)
  return passing ? <PassCentre props={props} /> : <AnimatedTrick props={props} flow={flow} />
}

/** The "↩ Fortryd" button of the video: lit while a suit is picked. */
function UndoButton({ flow }: { flow: PlayFlow }) {
  return (
    <button type="button" className={`proto-undo${flow.suit ? " is-on" : ""}`} disabled={!flow.suit} onClick={flow.cancel}>
      ↩ Fortryd
    </button>
  )
}

/** Next runde / play again, for the panel or bar; the pass button lives in the middle. */
function primaryAction(props: ProtoTableProps): { label: string; onClick: () => void } | null {
  const { view, finished } = derive(props)
  if (view.phase === "complete" && finished) return { label: "Spil igen", onClick: props.playAgain }
  if (view.phase === "complete") return { label: "Næste runde", onClick: props.nextRunde }
  return null
}

/** Moon choice, runde result and game over, on top of any variant. */
function Overlays(props: ProtoTableProps) {
  const { state } = props
  const { view, finished } = derive(props)
  if (view.phase === "choosing_moon")
    return (
      <div className="proto-overlay-host">
        <MoonChoice state={state} onChoose={props.chooseMoon} />
      </div>
    )
  if (view.phase !== "complete") return null
  return (
    <div className="proto-overlay-host">
      {finished ? <GameOver state={state} onPlayAgain={props.playAgain} onLeave={props.leaveNow} /> : <RundeResult state={state} onNext={props.nextRunde} />}
    </div>
  )
}

function LeaveButton({ props, className }: { props: ProtoTableProps; className: string }) {
  const [confirming, setConfirming] = useState(false)
  const { finished } = derive(props)
  if (confirming)
    return (
      <div className="proto-leave-confirm">
        <span>Forlad bordet? Du taber spillet.</span>
        <button type="button" className="proto-btn proto-btn-danger" onClick={props.leaveNow}>
          Ja, forlad
        </button>
        <button type="button" className="proto-btn" onClick={() => setConfirming(false)}>
          Bliv
        </button>
      </div>
    )
  return (
    <button type="button" className={className} onClick={() => (finished ? props.leaveNow() : setConfirming(true))}>
      Forlad bordet
    </button>
  )
}

function Backs({ count, vertical }: { count: number; vertical?: boolean }) {
  return (
    <div className={`proto-backs${vertical ? " is-vertical" : ""}`} aria-label={`${count} kort`}>
      {Array.from({ length: count }, (_, index) => (
        <CardBack key={index} size="sm" />
      ))}
    </div>
  )
}

function ScoreList({ state }: { state: TableState }) {
  const { score, seats } = state
  return (
    <table className="proto-score">
      <thead>
        <tr>
          <th>#</th>
          {seats.map((seat) => (
            <th key={seat.seat} className={score.leaders.includes(seat.seat) ? "is-lead" : ""}>
              {seat.name}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {score.rows.map((row) => (
          <tr key={row.number}>
            <td>{row.number}</td>
            {seats.map((seat) => (
              <td key={seat.seat}>{row.points[seat.seat] ?? 0}</td>
            ))}
          </tr>
        ))}
      </tbody>
      <tfoot>
        <tr>
          <td>I alt</td>
          {seats.map((seat) => (
            <td key={seat.seat} className={score.leaders.includes(seat.seat) ? "is-lead" : ""}>
              {score.totals[seat.seat] ?? 0}
            </td>
          ))}
        </tr>
      </tfoot>
    </table>
  )
}

/** The felt: a tap on empty felt cancels a picked suit, like in the video. */
function Felt({ flow, className, children }: { flow: PlayFlow; className: string; children: ReactNode }) {
  return (
    <div
      className={className}
      onClick={(event) => {
        if (flow.suit && !(event.target as HTMLElement).closest("button")) flow.cancel()
      }}
    >
      {children}
    </div>
  )
}

// ---------------------------------------------------------------------------
// A: the bridge layout. Felt with the stik in a framed square, name tags on
// its edges, opponents' hands as stacks at the edges; a fixed white panel
// on the right with tabs, points, last stik and two big buttons. On a
// narrow or portrait screen the panel becomes a bar under the felt.

export function VariantA(props: ProtoTableProps) {
  const { state } = props
  const { view, seatAt, nameOf, me, myTurn } = derive(props)
  const flow = usePlayFlow(props)
  const [tab, setTab] = useState<"spil" | "stilling" | "regler">("spil")
  const primary = primaryAction(props)
  const north = seatAt("north")
  const west = seatAt("west")
  const east = seatAt("east")
  const tag = (seat: SeatIndex | undefined, edge: Position) =>
    seat === undefined ? null : (
      <span className={`proto-a-tag proto-a-tag-${edge}${view.to_act === seat ? " is-active" : ""}`}>
        {seat === me ? "Dig" : nameOf(seat)}
      </span>
    )
  const taken = (seat: SeatIndex | undefined) => (seat === undefined ? 0 : (state.points_taken[seat] ?? 0))

  return (
    <div className="proto-stage proto-a">
      <Felt flow={flow} className="proto-a-felt">
        <div className="proto-a-north" data-proto-seat={north?.seat}>
          {north && <Backs count={view.card_counts[String(north.seat)] ?? 0} />}
        </div>
        <div className="proto-a-west" data-proto-seat={west?.seat}>
          {west && <Backs count={view.card_counts[String(west.seat)] ?? 0} vertical />}
        </div>
        <div className="proto-a-east" data-proto-seat={east?.seat}>
          {east && <Backs count={view.card_counts[String(east.seat)] ?? 0} vertical />}
        </div>

        <div className="proto-a-frame">
          {tag(north?.seat, "north")}
          {tag(west?.seat, "west")}
          {tag(east?.seat, "east")}
          {tag(me, "south")}
          <Centre props={props} flow={flow} />
          <span className="proto-a-corner proto-a-corner-left">
            {view.hearts_broken ? "♥ brudt" : "♥ ikke brudt"}
          </span>
          <span className="proto-a-corner proto-a-corner-right">
            {pointsLabel(taken(me))}
          </span>
        </div>

        <div className="proto-a-hand">
          <PlayHand props={props} flow={flow} />
        </div>
        <div className="proto-a-undo">
          <UndoButton flow={flow} />
        </div>
        {props.notice && <p className="proto-toast">{props.notice}</p>}
        <Overlays {...props} />
      </Felt>

      <aside className="proto-a-panel">
        <nav className="proto-a-tabs">
          {(["spil", "stilling", "regler"] as const).map((key) => (
            <button key={key} type="button" className={tab === key ? "is-on" : ""} onClick={() => setTab(key)}>
              <span aria-hidden="true">{{ spil: "🂠", stilling: "☰", regler: "⚙" }[key]}</span>
              {{ spil: "Spil", stilling: "Stilling", regler: "Regler" }[key]}
            </button>
          ))}
        </nav>
        <p className="proto-a-info">
          Øvebord · Runde {state.round_number} · bytning {DIRECTION_LABELS[view.pass_direction].toLowerCase()}
          {!props.connected && " · Forbinder…"}
        </p>

        {tab === "spil" && (
          <>
            <div className="proto-a-pills">
              {state.seats.map((seat) => (
                <div key={seat.seat} className={`proto-a-pill${view.to_act === seat.seat ? " is-active" : ""}`}>
                  <span>{seat.seat === me ? "Dig" : seat.name}</span>
                  <strong>{state.points_taken[seat.seat] ?? 0}</strong>
                  <small>i alt {state.score.totals[seat.seat] ?? 0}</small>
                </div>
              ))}
            </div>
            <div className="proto-a-lastbox">
              <h3 className="proto-a-h">Sidste stik</h3>
              <MiniCross props={props} plays={view.last_trick} />
            </div>
          </>
        )}
        {tab === "stilling" && <ScoreList state={state} />}
        {tab === "regler" && <p className="proto-a-status">{rulesSummary(state.rules)}</p>}

        <p className="proto-a-status">{myTurn && !flow.suit ? "Din tur: tryk på en kulør i hånden." : statusText(state, nameOf)}</p>
        <div className="proto-a-buttons">
          {primary && (
            <button type="button" className="proto-btn proto-btn-primary proto-btn-block" onClick={primary.onClick}>
              {primary.label}
            </button>
          )}
          <LeaveButton props={props} className="proto-btn proto-btn-danger proto-btn-block" />
        </div>
      </aside>
    </div>
  )
}

/** The last stik as a small cross, like "Sidste stik" in the video. */
function MiniCross({ props, plays }: { props: ProtoTableProps; plays: TrickPlay[] }) {
  const { positionOf } = derive(props)
  return (
    <div className="proto-mini">
      {plays.map((trickPlay) => (
        <div key={trickPlay.card} className={`proto-mini-${positionOf(trickPlay.seat)}`}>
          <Card {...parseCardCode(trickPlay.card)} size="sm" />
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// B: touch first. No panel: opponents as chips on top, the stik big in the
// middle, the hand and one fixed action bar with the status as its text.

export function VariantB(props: ProtoTableProps) {
  const { state } = props
  const { view, seats, me, nameOf, positionOf, myTurn } = derive(props)
  const flow = usePlayFlow(props)
  const [sheet, setSheet] = useState(false)
  const [menu, setMenu] = useState(false)
  const primary = primaryAction(props)
  const order: Position[] = ["west", "north", "east"]
  const opponents = seats.filter((seat) => seat.seat !== me).sort((a, b) => order.indexOf(positionOf(a.seat)) - order.indexOf(positionOf(b.seat)))

  return (
    <div className="proto-stage proto-b">
      <header className="proto-b-top">
        {opponents.map((seat) => (
          <div key={seat.seat} data-proto-seat={seat.seat} className={`proto-b-chip${view.to_act === seat.seat ? " is-active" : ""}`}>
            <span className="proto-b-avatar">{seat.name.slice(0, 1)}</span>
            <span className="proto-b-chip-text">
              <strong>{seat.name}</strong>
              <small>
                {view.card_counts[String(seat.seat)] ?? 0} kort · {pointsLabel(state.points_taken[seat.seat] ?? 0)}
              </small>
            </span>
          </div>
        ))}
        <button type="button" className="proto-b-menu" onClick={() => setMenu(!menu)} aria-label="Menu">
          ⋯
        </button>
        {menu && (
          <div className="proto-b-menu-panel">
            <button type="button" className="proto-btn proto-btn-block" onClick={() => setSheet(true)}>
              Stilling
            </button>
            <LeaveButton props={props} className="proto-btn proto-btn-danger proto-btn-block" />
          </div>
        )}
      </header>

      <Felt flow={flow} className="proto-b-middle">
        <Centre props={props} flow={flow} />
        {props.notice && <p className="proto-toast">{props.notice}</p>}
        <Overlays {...props} />
      </Felt>

      <div className="proto-b-hand">
        <PlayHand props={props} flow={flow} />
      </div>

      <footer className="proto-b-bar">
        <UndoButton flow={flow} />
        <div className="proto-b-me">
          <strong>Dig · {pointsLabel(state.points_taken[me] ?? 0)}</strong>
          <span>{myTurn && !flow.suit ? "Din tur: tryk på en kulør." : statusText(state, nameOf)}</span>
        </div>
        {primary ? (
          <button type="button" className="proto-btn proto-btn-primary proto-btn-xl" onClick={primary.onClick}>
            {primary.label}
          </button>
        ) : (
          <button type="button" className="proto-btn proto-btn-xl" onClick={() => setSheet(true)}>
            Stilling
          </button>
        )}
      </footer>

      {sheet && (
        <div className="proto-b-sheet" onClick={() => setSheet(false)}>
          <div className="proto-b-sheet-panel" onClick={(event) => event.stopPropagation()}>
            <div className="proto-b-grip" />
            <h2>Stilling · til {state.rules.end_score} point</h2>
            <ScoreList state={state} />
            <p className="proto-a-status">{rulesSummary(state.rules)}</p>
            <button type="button" className="proto-btn proto-btn-block" onClick={() => setSheet(false)}>
              Luk
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// C: overview. A light page with the score sheet always open on the side
// (a strip on top on narrow screens), a round table with four big seat
// cards, and the hand below the table.

export function VariantC(props: ProtoTableProps) {
  const { state } = props
  const { view, seatAt, nameOf, me, myTurn } = derive(props)
  const flow = usePlayFlow(props)
  const primary = primaryAction(props)
  const seatCard = (position: Position) => {
    const seat = seatAt(position)
    if (!seat) return null
    const isMe = seat.seat === me
    return (
      <div data-proto-seat={isMe ? undefined : seat.seat} className={`proto-c-seat proto-c-${position}${view.to_act === seat.seat ? " is-active" : ""}`}>
        <strong>{isMe ? "Dig" : seat.name}</strong>
        <span className="proto-c-big">{state.points_taken[seat.seat] ?? 0}</span>
        <small>{isMe ? `${view.hand.length} kort` : `${view.card_counts[String(seat.seat)] ?? 0} kort`}</small>
      </div>
    )
  }

  return (
    <div className="proto-stage proto-c">
      <aside className="proto-c-side">
        <h2>Øvebord · runde {state.round_number}</h2>
        <ScoreList state={state} />
        <p className="proto-c-rules">{rulesSummary(state.rules)}</p>
        <div className="proto-c-lastbox">
          <h3>Sidste stik</h3>
          <MiniCross props={props} plays={view.last_trick} />
        </div>
        <div className="proto-c-side-bottom">
          <LeaveButton props={props} className="proto-btn proto-btn-danger proto-btn-block" />
        </div>
      </aside>

      <Felt flow={flow} className="proto-c-main">
        <div className="proto-c-table">
          {seatCard("north")}
          {seatCard("west")}
          {seatCard("east")}
          {seatCard("south")}
          <div className="proto-c-felt">
            <Centre props={props} flow={flow} />
          </div>
          {props.notice && <p className="proto-toast">{props.notice}</p>}
          <Overlays {...props} />
        </div>
        <div className="proto-c-status">
          <UndoButton flow={flow} />
          <span>{myTurn && !flow.suit ? "Din tur: tryk på en kulør." : statusText(state, nameOf)}</span>
          {primary && (
            <button type="button" className="proto-btn proto-btn-primary" onClick={primary.onClick}>
              {primary.label}
            </button>
          )}
        </div>
        <div className="proto-c-hand">
          <PlayHand props={props} flow={flow} />
        </div>
      </Felt>
    </div>
  )
}
