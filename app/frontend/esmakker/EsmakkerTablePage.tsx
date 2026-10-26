import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react"
import { MotionConfig, motion } from "motion/react"
import { CardBack, CardFace, SuitIcon, type CardCode, type Suit } from "~/cards"
import { csrfToken } from "~/lobby/PostForm"
import { ChatLog, ChatSheet, UnreadBadge } from "~/table/Chat"
import { fanSpots, type HandSize } from "~/table/handLayout"
import type { ClientIntents, SeatIndex, ServerMessage, TrickPlay } from "~/table/messages"
import { SeatTag } from "~/table/SeatTag"
import { subscribeToTable, type TableSubscription } from "~/table/tableSubscription"
import { REJECTIONS } from "~/table/texts"
import { POSITIONS, Trick, type Position } from "~/table/Trick"
import { useTableChat, type TableChat } from "~/table/useTableChat"
import { useTimeline } from "~/table/useTimeline"
import { biddingHeadline, historyLabel, ladderRows, lastSaid, meldingLabel, turnText, type Names } from "./bidding"
import { EsmakkerRulesSummary } from "./EsmakkerSettings"
import type { BiddingChoices, BiddingView, EsmakkerTableState, EsmakkerView, RundeResultView, ScoreRow, TrumpCode } from "./messages"
import {
  aceChoiceTitle,
  aceLabel,
  acceptTrumpLabel,
  cardLabel,
  contractText,
  declarationText,
  playTurnText,
  resultText,
  roleOf,
  stikLabel,
  trumpChoiceTitle,
  trumpLabel,
  turnCardLabel,
} from "./play"
import { EsmakkerLookupTable, EsmakkerScoreModal, EsmakkerScoreSheet, EsmakkerStanding } from "./ScoreSheet"
import { runderPointsLine, sheetRows, signedPoints, totalPoints } from "./score"
import { fordaektLabel, fordaektOffer, fordaektWaiting } from "./fordaekt"
import { esmakkerFrames } from "./timeline"
import "~/table/table.css"
import "./esmakker.css"

const LOBBY_PATH = "/"
const CARD_MOVE = { type: "tween", duration: 0.2, ease: [0.2, 0.75, 0.3, 1] } as const
const DEAL_STAGGER = 0.035
const DISCARD_SIZE = 3

/**
 * The es-makker table: the same felt, frame, name tags and side panel as
 * the hjerterfri table. Your 13 cards as a fan at the bottom (jokers with
 * their own face), the others' cards as backs at the edges, the kitty
 * (katten) as three backs in the middle of the frame, and who deals and
 * who is forhånd on the name tags. It renders the state the server sends.
 *
 * The meldingsrunde: the middle of the frame shows the melding standing and
 * who holds it (then the melder, or the redeal), each name tag what that
 * seat said last, and the panel your choices on your turn (only those the
 * server offers: the meldinger on the ladder above the standing one, "Det
 * kan jeg selv", "Gå med", "Pas", and "Jernhånd" to its holder) and the
 * bidding so far.
 *
 * The play of a melding (ticket 03): the melder chooses trump and the ace
 * in the panel (only the server's choices), takes the kitty (its cards
 * ringed in her hand) and taps three cards to lay away; then the stik in
 * the middle, played by tapping a card the server allows. The melding,
 * trump and called ace stay in the frame's corner, each name tag shows its
 * stik and, once known, "melder" / "makker". At halve (ticket 06) the
 * melder calls the ace ("Jeg er makker til …"); its holder is "makker" on
 * every name tag at once, and she names trump and lays the kitty away the
 * same way (the melder herself, as selvmakker, when the ace lies in the
 * kitty). At vip (ticket 07) the melder calls the ace, then turns the
 * kitty's cards one by one ("Vend kort" / "Det er trumf" in the panel):
 * the turned cards lie face up in the middle for everyone, the rest as
 * backs, and the card taken as trump is ringed. Fordækt (ticket 04): a
 * melder the server offers it (void in the
 * ace's suit, before she leads) taps "Læg et kort fordækt" in the panel,
 * then a card in her hand; it lies face down by her side of the frame (its
 * face only to her) until she plays it, face down in the stik, turned over
 * once the stik is taken. The server's states are
 * played back at the pace of the card animations (timeline.ts). After the
 * runde its result shows over the felt; after the last runde the spil's
 * overview, and everyone goes on to the new bord (`next_path`).
 */
export function EsmakkerTablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  const [shown, push] = useTimeline(esmakkerFrames)
  const frame = shown?.frame ?? null
  const state = frame?.state ?? null
  const received = shown?.at ?? 0
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  // The version a choice was sent at: the choices wait for the next state.
  const [sentAt, setSentAt] = useState<number | null>(null)
  const [discardSelection, setDiscardSelection] = useState<CardCode[]>([])
  // The melder picks the card to lay fordækt (a tap in the hand lays it).
  const [choosingFordaekt, setChoosingFordaekt] = useState(false)
  const subscription = useRef<TableSubscription | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)
  // Once the spil is over: the new bord everyone waits at (state.next_path).
  const nextPath = useRef<string | null>(null)
  // Where cards fly from and sweep to: the stacks, your hand, and where you tapped your card.
  const seatEls = useAnchors<SeatIndex>()
  const playedFrom = useRef(new Map<CardCode, DOMRect>())
  const chat = useTableChat(userId, useCallback((text: string) => subscription.current?.send("chat", { text }), []))
  const receiveChat = chat.receive

  useEffect(() => {
    const handle = (message: ServerMessage) => {
      if (receiveChat(message)) return
      if (message.type === "closed") return window.location.assign(LOBBY_PATH)
      if (message.type === "waiting") return window.location.assign(message.path)
      if (message.type === "forladt") return window.location.reload()
      if (message.type === "rejected") {
        setSentAt(null)
        return setNotice(REJECTIONS[message.reason] ?? "Det kan du ikke her.")
      }
      if (message.type !== "state") return
      // An es-makker table is sent es-makker states (Game::State).
      const next = message.state as unknown as EsmakkerTableState
      if (next.next_path) nextPath.current = next.next_path
      push(next)
    }
    subscription.current = subscribeToTable(tableId, {
      onMessage: handle,
      onConnectionChange: setConnected,
      // The bord closed when the spil ended: a reconnect goes on to the new one.
      onRejected: () => (nextPath.current ? window.location.assign(nextPath.current) : setRefused(true)),
    })
    return () => subscription.current?.close()
  }, [tableId, receiveChat, push])

  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(null), 3500)
    return () => clearTimeout(timer)
  }, [notice])

  // A new runde starts with nothing chosen.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setDiscardSelection([])
    setChoosingFordaekt(false)
    playedFrom.current.clear()
  }, [rundeKey])

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
  const sentVersion = state?.version ?? null
  const playCard = useCallback(
    (card: CardCode, from: DOMRect | null) => {
      if (from) playedFrom.current.set(card, from)
      setSentAt(sentVersion)
      subscription.current?.send("play", { card })
    },
    [sentVersion],
  )
  const layFordaekt = useCallback(
    (card: CardCode) => {
      setSentAt(sentVersion)
      setChoosingFordaekt(false)
      subscription.current?.send("lay_fordaekt", { card })
    },
    [sentVersion],
  )
  const toggleDiscard = useCallback((card: CardCode) => {
    setDiscardSelection((current) =>
      current.includes(card) ? current.filter((code) => code !== card) : current.length < DISCARD_SIZE ? [...current, card] : current,
    )
  }, [])

  if (refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state || !frame) return <p className="table-loading">Henter bordet…</p>

  const { view, seats } = state
  const play = view.play
  const finished = state.status === "finished"
  const next = finished ? (state.next_path ?? null) : null
  const goNext = () => next && window.location.assign(next)
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex) => (seat === me ? "Dig" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const leave = () => leaveForm.current?.requestSubmit()
  const names: Names = { me, names: seats.map((seat) => seat.name) }
  const said = lastSaid(view.bidding.history)
  const choose: Choose = (action, ...data) => {
    setSentAt(state.version)
    subscription.current?.send(action, (data[0] ?? {}) as ClientIntents[typeof action])
  }
  const sent = sentAt === state.version
  const discarding = view.choices.discard
  const fordaektOffered = view.choices.fordaekt.length > 0
  const pickingFordaekt = choosingFordaekt && fordaektOffered && !sent
  const faceDown = fordaektWaiting(play)
  const playing = view.phase === "playing" || view.phase === "complete"
  const tagSaid = (seat: SeatIndex) => (seat === me ? undefined : playing && play ? undefined : said.get(seat))

  const tag = (position: Position) => {
    const seat = seatAt(position)
    if (!seat) return null
    return (
      <SeatTag
        key={position}
        info={seat}
        edge={position}
        label={
          <TagLabel
            name={nameOf(seat.seat)}
            dealer={!play && view.dealer === seat.seat}
            forhand={!play && view.forhand === seat.seat}
            said={tagSaid(seat.seat)}
            role={roleOf(seat.seat, view)}
            stik={playing && play ? stikLabel(play.tricks_won[seat.seat] ?? 0) : undefined}
          />
        }
        isMe={seat.seat === me}
        active={view.to_act === seat.seat}
        pass={null}
        receivedAt={received}
        timer={state.timer}
        said={chat.bubbles.get(seat.seat)}
      />
    )
  }
  const opponent = (position: Exclude<Position, "south">) => {
    const seat = seatAt(position)
    if (!seat) return null
    return <OpponentStack anchor={seatEls.ref(seat.seat)} position={position} name={seat.name} count={view.card_counts[String(seat.seat)] ?? 0} />
  }

  return (
    <MotionConfig reducedMotion="user">
      <section className="table-page esmakker-table" aria-label={`Bord ${state.table_id}`}>
        <div className="table-felt">
          {opponent("north")}
          {opponent("west")}
          {opponent("east")}

          <div className="table-frame">
            {POSITIONS.map(tag)}
            {playing && play ? (
              <Trick plays={frame.trick} sweepTo={frame.sweepTo} positionOf={positionOf} source={flightSource} seatRect={seatRect} />
            ) : (
              <div className="esmakker-centre">
                {play && play.turned.length > 0 && (view.phase === "turning" || view.phase === "discarding") ? (
                  <VipKitty turned={play.turned} hidden={view.kitty_count - play.turned.length} taken={play.vip_card} />
                ) : view.kitty_count > 0 && (
                  <div className="esmakker-kitty" role="img" aria-label={`Katten: ${view.kitty_count} kort`}>
                    {Array.from({ length: view.kitty_count }, (_, index) => (
                      <CardBack key={index} size="sm" />
                    ))}
                  </div>
                )}
                {play ? (
                  <DeclarationCentre view={view} names={names} selected={discardSelection.length} sent={sent} onDiscard={() => choose("discard", { cards: discardSelection })} />
                ) : (
                  <BiddingCentre bidding={view.bidding} names={names} />
                )}
              </div>
            )}
            {faceDown && play && (
              <FordaektOnTable
                code={faceDown.card}
                position={positionOf(faceDown.seat)}
                label={fordaektLabel(faceDown, play.called_ace, names)}
                playable={!sent && faceDown.card !== null && play.legal_moves.includes(faceDown.card)}
                onPlay={playCard}
              />
            )}
            {play ? (
              <Contract view={view} />
            ) : (
              <span className="table-corner table-corner-left">
                Runde {state.runde} af {state.runder}
              </span>
            )}
            <span className="table-corner table-corner-right">{play && playing ? stikCorner(view, names) : `Giver: ${nameOf(view.dealer)}`}</span>
          </div>

          <div ref={seatEls.ref(me)} className="table-hand-row">
            <EsmakkerHand
              key={`${state.game_id}:${state.round_number}`}
              cards={view.hand}
              legal={sent ? [] : pickingFordaekt ? view.choices.fordaekt : (play?.legal_moves ?? [])}
              kittyCards={play?.kitty_cards ?? []}
              discarding={discarding && !sent}
              selected={discardSelection}
              onPlay={pickingFordaekt ? layFordaekt : playCard}
              onToggle={toggleDiscard}
            />
          </div>

          <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
            {notice}
          </p>

          {view.phase === "complete" && view.result && (
            <div className="table-overlay-host">
              {finished ? (
                <FinalOverview state={state} names={names} onNext={goNext} onLeave={leave} />
              ) : (
                <RundeResultCard result={view.result} names={names} runde={state.runde} totals={state.score.totals} onNext={() => subscription.current?.send("next_runde", {})} />
              )}
            </div>
          )}
        </div>

        <EsmakkerSidePanel
          state={state}
          connected={connected}
          nameOf={nameOf}
          names={names}
          chat={chat}
          userId={userId}
          onLeave={leave}
          onChoose={choose}
          sent={sent}
          choosingFordaekt={pickingFordaekt}
          onToggleFordaekt={() => setChoosingFordaekt((current) => !current)}
        />

        <form ref={leaveForm} method="post" action={next ? `${next}/departure` : departurePath} hidden>
          <input type="hidden" name="authenticity_token" value={csrfToken()} />
        </form>
      </section>
    </MotionConfig>
  )
}

/**
 * A name tag's text: the name, "giver" / "forhånd" as markers, and what the
 * seat said last in the meldingsrunde; in the play its role once known
 * ("melder", "makker") and its stik.
 */
function TagLabel(props: { name: string; dealer: boolean; forhand: boolean; said: string | undefined; role: string | null; stik: string | undefined }) {
  const { name, dealer, forhand, said, role, stik } = props
  return (
    <>
      {name}
      {dealer && <span className="esmakker-role">giver</span>}
      {forhand && <span className="esmakker-role is-forhand">forhånd</span>}
      {role && <span className="esmakker-role is-melder">{role}</span>}
      {said && <span className="esmakker-said">{said}</span>}
      {stik && <span className="esmakker-said">{stik}</span>}
    </>
  )
}

type ChoiceAction = "bid" | "pas" | "det_kan_jeg_selv" | "gaa_med" | "claim_jernhaand" | "choose_trump" | "call_ace" | "turn_card" | "accept_trump" | "discard"
/** Sends a choice; the intents without data take none. */
type Choose = <A extends ChoiceAction>(action: A, ...data: ClientIntents[A] extends Record<string, never> ? [] : [ClientIntents[A]]) => void

/** A suit's icon in its colour. */
function SuitMark({ suit }: { suit: Suit }) {
  return <SuitIcon suit={suit} className={`esmakker-suit${suit === "D" || suit === "H" ? " hf-red" : ""}`} />
}

/** Trump in a short form: the suit's icon, or "trumfløs". */
function TrumpMark({ trump }: { trump: TrumpCode }) {
  return trump === "trumfloes" ? <>trumfløs</> : <SuitMark suit={trump} />
}

/** The frame's corner during the play: the melding, trump and the called ace, always in sight. */
function Contract({ view }: { view: EsmakkerView }) {
  const play = view.play
  const text = contractText(view)
  if (!play || !text) return null
  const melding = view.bidding.outcome?.kind === "melder" ? meldingLabel(view.bidding.outcome.melding) : ""
  return (
    <span className="table-corner table-corner-left esmakker-contract" aria-label={text}>
      <strong>{melding}</strong>
      {play.trump && (
        <span>
          Trumf <TrumpMark trump={play.trump} />
        </span>
      )}
      {play.called_ace && (
        <span>
          Es <SuitMark suit={play.called_ace} />
        </span>
      )}
    </span>
  )
}

/** The frame's right corner during the stik: the stik per side once you know the sides, otherwise yours. */
function stikCorner(view: EsmakkerView, names: Names): string {
  const play = view.play
  if (!play) return ""
  if (play.side_stik) return `Melder ${play.side_stik.melder} · Mod ${play.side_stik.modspillere}`
  return `Dine stik: ${play.tricks_won[names.me] ?? 0}`
}

/**
 * Vip's kitty in the middle of the frame: the cards turned so far face up
 * for everyone, in order, the rest as backs (hidden from all until the
 * melder takes the kitty up); the card taken as trump is ringed.
 */
function VipKitty({ turned, hidden, taken }: { turned: CardCode[]; hidden: number; taken: number | null }) {
  const label = `Vendt fra katten: ${turned.map(cardLabel).join(", ")}`
  return (
    <div className="esmakker-vip-kitty" role="img" aria-label={label}>
      {turned.map((code, index) => (
        <CardFace key={code} code={code} size="sm" className={taken === index + 1 ? "is-trump" : undefined} />
      ))}
      {Array.from({ length: Math.max(hidden, 0) }, (_, index) => (
        <CardBack key={`back-${index}`} size="sm" />
      ))}
    </div>
  )
}

/** The middle of the frame while the melder declares; she lays three cards away from here. */
function DeclarationCentre(props: { view: EsmakkerView; names: Names; selected: number; sent: boolean; onDiscard: () => void }) {
  const { view, names, selected, sent, onDiscard } = props
  const text = declarationText(view, names)
  if (!text) return null
  return (
    <div className="esmakker-bidding is-done" aria-live="polite">
      <p className="esmakker-bidding-label">{text.headline}</p>
      <p className="esmakker-bidding-melding">{contractText(view)}</p>
      <p className="esmakker-bidding-detail">{text.detail}</p>
      {view.choices.discard && (
        <button type="button" className="table-btn table-btn-primary esmakker-discard" disabled={sent || selected !== DISCARD_SIZE} onClick={onDiscard}>
          Læg {selected === DISCARD_SIZE ? "de 3" : `${selected} af 3`} kort væk
        </button>
      )}
    </div>
  )
}

/**
 * The declarer's choices after the meldingsrunde, exactly those the server
 * offers: trump (the suits and trumfløs), then the aces the melder may
 * call; while she lays away, what to do in the hand. At halve the melder
 * calls the ace ("jeg er makker til …") and its holder, the makker, names
 * trump and lays away. At vip, after the ace, "Det er trumf" for the card
 * turned last and "Vend kort" for the next.
 */
function DeclarationBox({ view, sent, onChoose }: { view: EsmakkerView; sent: boolean; onChoose: Choose }) {
  const choices = view.choices
  const outcome = view.bidding.outcome
  const melder = outcome?.kind === "melder" && outcome.melder === view.seat
  return (
    <div className="esmakker-box" role="group" aria-label={melder ? "Dine valg som melder" : "Dine valg som makker"}>
      {choices.trumps.length > 0 && (
        <>
          <p className="esmakker-box-title">{trumpChoiceTitle(view)}</p>
          <div className="esmakker-choice-row">
            {choices.trumps.map((trump) => (
              <button key={trump} type="button" className={`esmakker-melding${trump === "trumfloes" ? " is-wide" : ""}`} aria-label={trumpLabel(trump)} disabled={sent} onClick={() => onChoose("choose_trump", { trump })}>
                <TrumpMark trump={trump} />
              </button>
            ))}
          </div>
        </>
      )}
      {choices.aces.length > 0 && (
        <>
          <p className="esmakker-box-title">{aceChoiceTitle(outcome?.kind === "melder" ? outcome.melding : null)}</p>
          <div className="esmakker-choice-row">
            {choices.aces.map((suit) => (
              <button key={suit} type="button" className="esmakker-melding" aria-label={aceLabel(suit)} disabled={sent} onClick={() => onChoose("call_ace", { suit })}>
                A <SuitMark suit={suit} />
              </button>
            ))}
          </div>
        </>
      )}
      {(choices.turn_card || choices.accept_trump) && (
        <>
          <p className="esmakker-box-title">Find trumf i katten</p>
          <div className="esmakker-choice-row esmakker-vip-choices">
            {choices.accept_trump && (
              <button type="button" className="table-btn table-btn-primary" disabled={sent} onClick={() => onChoose("accept_trump")}>
                {acceptTrumpLabel(view.play?.turned ?? [])}
              </button>
            )}
            {choices.turn_card && (
              <button type="button" className="table-btn" disabled={sent} onClick={() => onChoose("turn_card")}>
                {turnCardLabel(view.play?.turned.length ?? 0)}
              </button>
            )}
          </div>
        </>
      )}
      {choices.discard && <p className="esmakker-box-title">Tryk på 3 kort i hånden, og læg dem væk. Ingen ser dem.</p>}
    </div>
  )
}

/**
 * The melder's offer of fordækt (only when the server makes it): what it
 * does, and the button that lets her pick the card in her hand.
 */
function FordaektBox({ calledAce, choosing, sent, onToggle }: { calledAce: Suit; choosing: boolean; sent: boolean; onToggle: () => void }) {
  const { title, detail } = fordaektOffer(calledAce)
  return (
    <div className="esmakker-box esmakker-fordaekt-box" role="group" aria-label="Fordækt">
      <p className="esmakker-box-title">{title}</p>
      <p className="esmakker-fordaekt-detail">{choosing ? "Tryk på det kort i hånden, du vil lægge fordækt." : detail}</p>
      <button type="button" className={`table-btn${choosing ? "" : " table-btn-primary"}`} disabled={sent} onClick={onToggle}>
        {choosing ? "Fortryd" : "Læg et kort fordækt"}
      </button>
    </div>
  )
}

/**
 * The fordækt card lying face down by the melder's side of the frame
 * until she plays it: its back to the others, its face (ringed as face
 * down) to her, playable when the server allows.
 */
function FordaektOnTable(props: { code: CardCode | null; position: Position; label: string; playable: boolean; onPlay: (card: CardCode, from: DOMRect | null) => void }) {
  const { code, position, label, playable, onPlay } = props
  const own = useRef<HTMLDivElement | null>(null)
  return (
    <div ref={own} className={`esmakker-fordaekt esmakker-fordaekt-${position}`} role="img" aria-label={label} title={label}>
      {code ? (
        <CardFace code={code} size="sm" state={playable ? "playable" : "idle"} className="is-face-down" onClick={playable ? () => onPlay(code, own.current?.getBoundingClientRect() ?? null) : undefined} />
      ) : (
        <CardBack size="sm" />
      )}
      <span className="esmakker-fordaekt-label">Fordækt</span>
    </div>
  )
}

/** The runde just played, shown over the felt until the next runde is dealt. */
function RundeResultCard({ result, names, runde, totals, onNext }: { result: RundeResultView; names: Names; runde: number; totals: number[] | null; onNext: () => void }) {
  const { headline, detail } = resultText(result, names)
  const tone = result.kind === "played" ? (result.gik_hjem ? " is-home" : " is-bet") : ""
  return (
    <div className={`table-overlay esmakker-result${tone}`} role="dialog" aria-labelledby="esmakker-result-title">
      <p className="esmakker-bidding-label">Runde {runde} er slut</p>
      <h2 id="esmakker-result-title">{headline}</h2>
      <p className="table-overlay-note">{detail}</p>
      {result.kind === "played" && (
        <ul className="esmakker-result-stik">
          {runderPointsLine(result, names.names).map(({ seat, name, points }) => (
            <li key={seat} className={[result.melder, result.esmakker].includes(seat) ? "is-side" : undefined}>
              <span>{seat === names.me ? "Dig" : name}</span>
              <small>{stikLabel(result.tricks_won[seat] ?? 0)}</small>
              <strong className={(result.points[seat] ?? 0) > 0 ? "is-won" : (result.points[seat] ?? 0) < 0 ? "is-lost" : undefined}>{points}</strong>
            </li>
          ))}
        </ul>
      )}
      {totals && (
        <p className="table-overlay-note esmakker-result-totals">
          I alt: {totals.map((total, seat) => `${seat === names.me ? "dig" : (names.names[seat] ?? "")} ${totalPoints(total)}`).join(" · ")}
        </p>
      )}
      <p className="table-overlay-note">{result.kind === "played" ? "Næste runde starter om lidt." : "Runden giver 0 point. Næste runde starter om lidt."}</p>
      <button type="button" onClick={onNext}>
        Næste runde
      </button>
    </div>
  )
}

/** The end of the spil: every runde's melding and how it went; everyone goes on to the new bord. */
function FinalOverview({ state, names, onNext, onLeave }: { state: EsmakkerTableState; names: Names; onNext: () => void; onLeave: () => void }) {
  const last = state.view.result
  return (
    <div className="table-overlay esmakker-overview" role="dialog" aria-labelledby="esmakker-overview-title">
      <h2 id="esmakker-overview-title">Spillet er slut</h2>
      {last && <p className="table-overlay-note">Sidste runde: {resultText(last, names).headline}.</p>}
      <EsmakkerStanding totals={state.score.totals} names={state.seats.map((seat) => seat.name)} me={state.view.seat} />
      <EsmakkerScoreSheet results={state.score.results} names={state.seats.map((seat) => seat.name)} totals={state.score.totals} leaders={state.score.leaders} me={state.view.seat} />
      <p className="table-overlay-note">I sidder nu ved et nyt bord i lobbyen. Bliv siddende for at spille igen, eller rejs dig.</p>
      <div className="table-overlay-buttons">
        <button type="button" onClick={onNext} disabled={!state.next_path}>
          Til bordet
        </button>
        <button type="button" onClick={onLeave}>
          Forlad bordet
        </button>
      </div>
    </div>
  )
}

/** The runder so far, in short for the panel: melder, melding, stik, how it went and your points (the whole sheet is under Stilling). */
function RunderTable({ results, names, me }: { results: ScoreRow[]; names: string[]; me: SeatIndex }) {
  const rows = sheetRows(results, names)
  if (rows.length === 0) return null
  return (
    <div className="esmakker-runder is-compact">
      <h3>Runder</h3>
      <table className="table-score">
        <tbody>
          {rows.map((row) => (
            <tr key={row.number}>
              <td>{row.number}</td>
              <th scope="row">{row.melder}</th>
              <td>{row.melding}</td>
              <td>{row.stik === "–" ? "" : stikLabel(Number(row.stik))}</td>
              <td>
                <strong>{row.outcome}</strong>
              </td>
              <td title="Dine point">{signedPoints(row.points[me] ?? 0)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/** The middle of the frame: the melding standing and who holds it, or how the meldingsrunde ended. */
function BiddingCentre({ bidding, names }: { bidding: BiddingView; names: Names }) {
  const { headline, detail } = biddingHeadline(bidding, names)
  const turn = turnText(bidding, names)
  const done = bidding.outcome !== null
  return (
    <div className={`esmakker-bidding${done ? " is-done" : ""}`} aria-live="polite">
      <p className="esmakker-bidding-label">{done ? "Meldingsrunden er slut" : "Melding"}</p>
      <p className="esmakker-bidding-melding">{headline}</p>
      {detail && <p className="esmakker-bidding-detail">{detail}</p>}
      {turn && <p className="esmakker-bidding-turn">{turn}</p>}
    </div>
  )
}

/**
 * Your choices in the meldingsrunde, exactly those the server offers: the
 * meldinger in ladder order, one row per number; "Det kan jeg selv" with
 * the melding it takes over; "Gå med" on a sol-melding; "Pas"; and
 * "Jernhånd" to its holder before the first bid.
 */
function BiddingBox(props: { choices: BiddingChoices; melding: string | null; pahaengOrder: string[]; sent: boolean; onChoose: Choose }) {
  const { choices, melding, pahaengOrder, sent, onChoose } = props
  const rows = ladderRows(choices.meldinger, pahaengOrder)
  return (
    <div className="esmakker-box" role="group" aria-label="Dine valg i meldingsrunden">
      {choices.jernhaand && (
        <button type="button" className="table-btn esmakker-jernhaand" disabled={sent} onClick={() => onChoose("claim_jernhaand")}>
          Jernhånd: giv kortene om
        </button>
      )}
      {choices.det_kan_jeg_selv && (
        <button type="button" className="table-btn table-btn-primary" disabled={sent} onClick={() => onChoose("det_kan_jeg_selv")}>
          Det kan jeg selv{melding ? ` (${meldingLabel(melding)})` : ""}
        </button>
      )}
      {choices.gaa_med && (
        <button type="button" className="table-btn esmakker-gaa-med" disabled={sent} onClick={() => onChoose("gaa_med")}>
          Gå med
        </button>
      )}
      {rows.length > 0 && (
        <div className="esmakker-ladder" role="group" aria-label="Meld">
          {rows.map((row, index) => (
            <div key={row.cells[0]?.code ?? index} className={`esmakker-ladder-row${row.number === null ? " is-sol" : ""}`}>
              {row.number !== null && row.cells[0]?.column !== 1 && (
                <span className="esmakker-ladder-number" aria-hidden="true">
                  {row.number}
                </span>
              )}
              {row.cells.map((cell) => (
                <button
                  key={cell.code}
                  type="button"
                  className="esmakker-melding"
                  style={row.number === null ? undefined : { gridColumn: cell.column }}
                  aria-label={meldingLabel(cell.code)}
                  disabled={sent}
                  onClick={() => onChoose("bid", { melding: cell.code })}
                >
                  {cell.text}
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
      {choices.pas && (
        <button type="button" className="table-btn esmakker-pas" disabled={sent} onClick={() => onChoose("pas")}>
          Pas
        </button>
      )}
    </div>
  )
}

/** The meldingsrunde so far, one line per step. */
function BiddingHistory({ bidding, nameOf }: { bidding: BiddingView; nameOf: (seat: SeatIndex) => string }) {
  if (bidding.history.length === 0) return null
  return (
    <div className="esmakker-history">
      <h3>Meldinger</h3>
      <ol>
        {bidding.history.map((entry, index) => (
          <li key={index} className={`is-${entry.action}`}>
            <span>{nameOf(entry.seat)}</span>
            <strong>{historyLabel(entry)}</strong>
          </li>
        ))}
      </ol>
    </div>
  )
}

/** Another seat's hand: card backs at the edge of the felt; played cards fly from here. */
const OpponentStack = memo(function OpponentStack(props: { anchor: (element: HTMLElement | null) => void; position: Exclude<Position, "south">; name: string; count: number }) {
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
 * Your hand as the fan of the hjerterfri table (handLayout); dealt cards
 * rise into place one after another. In the stik a tap plays a card the
 * server allows (the others are greyed on your turn); while the melder
 * lays away, a tap picks a card (it rises) or puts it back, and the
 * kitty's cards are ringed.
 */
const EsmakkerHand = memo(function EsmakkerHand(props: {
  cards: CardCode[]
  legal: CardCode[]
  kittyCards: CardCode[]
  discarding: boolean
  selected: CardCode[]
  onPlay: (card: CardCode, from: DOMRect | null) => void
  onToggle: (card: CardCode) => void
}) {
  const { cards, legal, kittyCards, discarding, selected, onPlay, onToggle } = props
  const [size, sizer, row] = useHandSize()
  const spots = size ? fanSpots(cards.length, size) : []
  const myTurn = legal.length > 0
  return (
    <div ref={row} className={`table-hand${myTurn ? " is-turn" : ""}`} aria-label="Dine kort">
      <div ref={sizer} className="table-hand-sizer" aria-hidden="true" />
      {cards.map((code, index) => {
        const spot = spots[index]
        if (!spot) return null
        const chosen = selected.includes(code)
        const playable = legal.includes(code)
        const state = discarding ? (chosen ? "selected" : "playable") : myTurn ? (playable ? "playable" : "disabled") : "idle"
        const onClick = discarding ? () => onToggle(code) : playable ? (element: HTMLElement | null) => onPlay(code, element?.getBoundingClientRect() ?? null) : undefined
        return (
          <motion.div
            key={code}
            className="table-hand-card"
            initial={{ ...spot, y: spot.y + 40, opacity: 0 }}
            animate={{ ...spot, opacity: 1 }}
            transition={{ ...CARD_MOVE, delay: index * DEAL_STAGGER }}
          >
            <HandCard code={code} state={state} isNew={kittyCards.includes(code)} onClick={onClick} />
          </motion.div>
        )
      })}
    </div>
  )
})

/** One card in the hand; a click hands over the card's element, so a played card flies from where it lay. */
function HandCard({ code, state, isNew, onClick }: { code: CardCode; state: "idle" | "playable" | "selected" | "disabled"; isNew: boolean; onClick: ((element: HTMLElement | null) => void) | undefined }) {
  const face = useRef<HTMLDivElement | null>(null)
  return (
    <div ref={face}>
      <CardFace code={code} state={state} isNew={isNew} onClick={onClick ? () => onClick(face.current) : undefined} />
    </div>
  )
}

/** The hand row's width and the card width, measured before paint and on resize. */
function useHandSize() {
  const sizer = useRef<HTMLDivElement | null>(null)
  const row = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState<HandSize | null>(null)
  useLayoutEffect(() => {
    const measure = () => {
      const width = row.current?.clientWidth ?? 0
      const cw = sizer.current?.offsetWidth ?? 0
      setSize((current) => (current && current.width === width && current.cw === cw ? current : { width, cw }))
    }
    measure()
    const observer = new ResizeObserver(measure)
    if (row.current) observer.observe(row.current)
    if (sizer.current) observer.observe(sizer.current)
    return () => observer.disconnect()
  }, [])
  return [size, sizer, row] as const
}

type Tab = "spil" | "stilling" | "regler" | "chat"
const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: "spil", label: "Spil", icon: "🂠" },
  { key: "stilling", label: "Stilling", icon: "☰" },
  { key: "regler", label: "Regler", icon: "⚙" },
  { key: "chat", label: "Chat", icon: "✉" },
]
const NARROW = "(max-width: 820px), (orientation: portrait)"

/**
 * The white panel beside the felt, as at hjerterfri: the spil (each seat
 * with its points and role in the runde), the bord's rules, the chat, the
 * status line and "Forlad bordet". On a narrow screen a bar under the felt.
 */
function EsmakkerSidePanel(props: {
  state: EsmakkerTableState
  connected: boolean
  nameOf: (seat: SeatIndex) => string
  names: Names
  chat: TableChat
  userId: number
  onLeave: () => void
  onChoose: Choose
  sent: boolean
  choosingFordaekt: boolean
  onToggleFordaekt: () => void
}) {
  const { state, connected, nameOf, names, chat, userId, onLeave, onChoose, sent, choosingFordaekt, onToggleFordaekt } = props
  const { view, seats } = state
  const [tab, setTab] = useState<Tab>("spil")
  const [chatSheet, setChatSheet] = useState(false)
  const [scoreModal, setScoreModal] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const narrow = useMediaQuery(NARROW)
  const { setViewing } = chat
  useEffect(() => {
    if (narrow && tab === "chat") {
      setTab("spil")
      setChatSheet(true)
    }
  }, [narrow, tab])
  useEffect(() => setViewing(chatSheet || (!narrow && tab === "chat")), [setViewing, chatSheet, narrow, tab])

  const role = (seat: SeatIndex): ReactNode => (seat === view.dealer ? "Giver" : seat === view.forhand ? "Forhånd" : " ")

  return (
    <aside className="table-panel" aria-label="Spillet">
      <nav className="table-tabs" aria-label="Faner">
        {TABS.map((item) => (
          <button key={item.key} type="button" className={tab === item.key ? "is-on" : undefined} aria-pressed={tab === item.key} onClick={() => setTab(item.key)}>
            <span aria-hidden="true">{item.icon}</span>
            {item.label}
            {item.key === "chat" && tab !== "chat" && <UnreadBadge count={chat.unread} />}
          </button>
        ))}
      </nav>
      <p className="table-panel-info">
        <a href="/" className="table-lobby-link">
          ‹ Lobby
        </a>{" "}
        · Es-makker · Bord {state.table_id} · Runde {state.runde} af {state.runder}
        {!connected && <span className="table-offline"> · Forbinder…</span>}
      </p>

      <div className={`table-panel-body${tab === "spil" ? " is-spil" : ""}${tab === "chat" ? " is-chat" : ""}${hasChoices(view.choices) ? " has-choices" : ""}`}>
        {tab === "spil" && (
          <>
            <div className="table-pills">
              {seats.map((seat) => (
                <div key={seat.seat} className={`table-pill${view.to_act === seat.seat ? " is-active" : ""}${state.score.leaders.includes(seat.seat) ? " is-leader" : ""}`}>
                  <span>{nameOf(seat.seat)}</span>
                  <strong>{totalPoints(state.score.totals[seat.seat] ?? 0)}</strong>
                  <small>{role(seat.seat)}</small>
                </div>
              ))}
            </div>
            {hasBiddingChoices(view.choices) && <BiddingBox choices={view.choices} melding={view.bidding.melding} pahaengOrder={state.rules.pahaeng_order} sent={sent} onChoose={onChoose} />}
            {hasDeclarationChoices(view.choices) && <DeclarationBox view={view} sent={sent} onChoose={onChoose} />}
            {view.choices.fordaekt.length > 0 && view.play?.called_ace && (
              <FordaektBox calledAce={view.play.called_ace} choosing={choosingFordaekt} sent={sent} onToggle={onToggleFordaekt} />
            )}
            {view.play ? <RunderTable results={state.score.results} names={seats.map((seat) => seat.name)} me={view.seat} /> : <BiddingHistory bidding={view.bidding} nameOf={nameOf} />}
          </>
        )}
        {tab === "stilling" && (
          <div className="table-panel-score esmakker-panel-score">
            <p>Point vindes og tabes mellem spillerne; summen er altid 0. Højeste total vinder.</p>
            <EsmakkerScoreSheet results={state.score.results} names={seats.map((seat) => seat.name)} totals={state.score.totals} leaders={state.score.leaders} me={view.seat} />
            <EsmakkerLookupTable points={state.rules.points} />
          </div>
        )}
        {tab === "regler" && (
          <div className="table-panel-rules esmakker-panel-rules">
            <EsmakkerRulesSummary rules={state.rules} runder={state.runder} />
          </div>
        )}
        {tab === "chat" && !narrow && <ChatLog chat={chat} userId={userId} />}
      </div>

      <p className="table-status" aria-live="polite">
        {status(view, names)}
      </p>
      <div className="table-panel-buttons">
        <button type="button" className="table-btn table-panel-chat-button" onClick={() => setChatSheet(true)}>
          Chat
          <UnreadBadge count={chat.unread} />
        </button>
        <button type="button" className="table-btn table-panel-score-button" onClick={() => setScoreModal(true)}>
          Stilling
        </button>
        {confirmLeave ? (
          <div className="table-leave-confirm" role="alertdialog" aria-label="Forlad bordet">
            <span>Forlad bordet? Du taber spillet og kan ikke vende tilbage til det.</span>
            <button type="button" className="table-btn table-btn-danger" onClick={onLeave}>
              Ja, forlad
            </button>
            <button type="button" className="table-btn" onClick={() => setConfirmLeave(false)}>
              Bliv
            </button>
          </div>
        ) : (
          <button type="button" className="table-btn table-btn-danger" onClick={() => setConfirmLeave(true)}>
            Forlad bordet
          </button>
        )}
      </div>
      {chatSheet && <ChatSheet chat={chat} userId={userId} onClose={() => setChatSheet(false)} />}
      {scoreModal && (
        <EsmakkerScoreModal
          results={state.score.results}
          names={seats.map((seat) => seat.name)}
          totals={state.score.totals}
          leaders={state.score.leaders}
          me={view.seat}
          points={state.rules.points}
          onClose={() => setScoreModal(false)}
        />
      )}
    </aside>
  )
}

const hasBiddingChoices = (choices: BiddingChoices) => choices.pas || choices.jernhaand || choices.det_kan_jeg_selv || choices.gaa_med || choices.meldinger.length > 0
const hasDeclarationChoices = (choices: BiddingChoices) =>
  choices.trumps.length > 0 || choices.aces.length > 0 || choices.turn_card || choices.accept_trump || choices.discard
const hasChoices = (choices: BiddingChoices) => hasBiddingChoices(choices) || hasDeclarationChoices(choices) || choices.fordaekt.length > 0

/** The status line: whose turn, what the melder does, how the runde ended. */
function status(view: EsmakkerView, names: Names): string {
  if (view.result) return resultText(view.result, names).headline
  const declaring = declarationText(view, names)
  if (declaring) return declaring.detail
  const playTurn = playTurnText(view, names)
  if (playTurn) return playTurn
  const turn = turnText(view.bidding, names)
  if (turn) return turn
  const { headline, detail } = biddingHeadline(view.bidding, names)
  return detail ? `${headline}. ${detail}` : headline
}

/**
 * Elements by key, for measuring where a card flies from or to. The ref
 * callbacks are stable per key (as at the hjerterfri table).
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

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches)
  useEffect(() => {
    const list = window.matchMedia(query)
    const change = () => setMatches(list.matches)
    change()
    list.addEventListener("change", change)
    return () => list.removeEventListener("change", change)
  }, [query])
  return matches
}
