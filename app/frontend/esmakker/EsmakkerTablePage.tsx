import { memo, useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import { MotionConfig, motion } from "motion/react"
import { CardBack, CardFace, SuitIcon, type CardCode, type Suit } from "~/cards"
import { fanSpots } from "~/table/handLayout"
import type { ClientIntents, SeatIndex } from "~/table/messages"
import { SeatTag } from "~/table/SeatTag"
import { LeaveForm, OpenHand, OpponentStack, TablePanel, TableToasts, revealedHand, useHandSize, useTableShell, useThoughtLog, useTrickAnchors, VisKortBox } from "~/table/shell"
import { POSITIONS, Trick, type Position } from "~/table/Trick"
import type { TableChat } from "~/table/useTableChat"
import { useTimeline } from "~/table/useTimeline"
import { useNow } from "~/table/turnTimer"
import { bankButtonLabel, bankFactor, bankLines, bankSecondsLeft, countdownFraction, countdownSeconds } from "./bank"
import { biddingHeadline, historyLabel, ladderRows, lastSaid, meldingLabel, turnText, type Names } from "./bidding"
import { EsmakkerRulesSummary } from "./EsmakkerSettings"
import type { BankWindow, BiddingChoices, BiddingView, EsmakkerTableState, EsmakkerView, RundeResultView, ScoreRow, TrumpCode } from "./messages"
import {
  aceChoiceTitle,
  aceLabel,
  acceptTrumpLabel,
  cardLabel,
  contractSentence,
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
import { discardButtonText, discardSize, openHandAt, openHandLabel, solAllowedText, solPlay, solPlayersText, solStatus } from "./sol"
import { esmakkerFrames } from "./timeline"
import { esmakkerThoughtLine } from "./visKort"
import "~/table/table.css"
import "./esmakker.css"

const CARD_MOVE = { type: "tween", duration: 0.2, ease: [0.2, 0.75, 0.3, 1] } as const
const DEAL_STAGGER = 0.035

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
 * backs, and the card taken as trump is ringed. Then the bank window
 * (ticket 08): a countdown in the middle for everyone, "Bank" under it for
 * the seats the server offers it (the same to the three non-melders, so
 * the esmakker is not given away; the melder's "Bank igen" after a bank),
 * and who banked (×2/×4) in the frame's corner. Fordækt (ticket 04): a
 * melder the server offers it (void in the
 * ace's suit, before she leads) taps "Læg et kort fordækt" in the panel,
 * then a card in her hand; it lies face down by her side of the frame (its
 * face only to her) until she plays it, then face down in the stik; it is
 * never turned for the others. The server's states are
 * played back at the pace of the card animations (timeline.ts). After the
 * runde its result shows over the felt; after the last runde the spil's
 * overview, and everyone goes on to the new bord (`next_path`).
 *
 * The subscription, the panel's frame, the toasts (the tur-ur's warning
 * too), leaving, the open hands and "Vis kort" (an admin alone with bots
 * sees their hands face up and their thoughts, worded here) are the table
 * shell's (~/table/shell), the same as at hjerterfri; the rest is
 * es-makker's.
 */
export function EsmakkerTablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  const [shown, push] = useTimeline(esmakkerFrames)
  const frame = shown?.frame ?? null
  const state = frame?.state ?? null
  const received = shown?.at ?? 0
  // The version a choice was sent at: the choices wait for the next state.
  const [sentAt, setSentAt] = useState<number | null>(null)
  const [discardSelection, setDiscardSelection] = useState<CardCode[]>([])
  // The melder picks the card to lay fordækt (a tap in the hand lays it).
  const [choosingFordaekt, setChoosingFordaekt] = useState(false)
  const shell = useTableShell<EsmakkerTableState>({ tableId, userId, onState: push, onRejected: () => setSentAt(null) })
  const { chat, send } = shell
  // Where cards fly from and sweep to: the stacks, your hand, and where you tapped your card.
  const me = state?.view.seat ?? 0
  const { seats: seatEls, playedFrom, positionOf, seatRect, flightSource } = useTrickAnchors(me)
  // "Vis kort": the bots' thoughts this runde, as the states are shown.
  const thoughts = useThoughtLog(state?.vis_kort, state?.round_number ?? 0)

  // A new runde starts with nothing chosen.
  const rundeKey = state ? `${state.game_id}:${state.round_number}` : ""
  useEffect(() => {
    setDiscardSelection([])
    setChoosingFordaekt(false)
    playedFrom.current.clear()
  }, [rundeKey, playedFrom])
  // Once the cards are laid away (and the kitty's arrive), nothing is picked.
  const layingAway = state?.view.choices.discard ?? false
  useEffect(() => {
    if (!layingAway) setDiscardSelection([])
  }, [layingAway])

  const sentVersion = state?.version ?? null
  const playCard = useCallback(
    (card: CardCode, from: DOMRect | null) => {
      if (from) playedFrom.current.set(card, from)
      setSentAt(sentVersion)
      send("play", { card })
    },
    [sentVersion, playedFrom, send],
  )
  const layFordaekt = useCallback(
    (card: CardCode) => {
      setSentAt(sentVersion)
      setChoosingFordaekt(false)
      send("lay_fordaekt", { card })
    },
    [sentVersion, send],
  )
  const laySize = state ? discardSize(state.view) : 3
  const toggleDiscard = useCallback(
    (card: CardCode) => {
      setDiscardSelection((current) =>
        current.includes(card) ? current.filter((code) => code !== card) : current.length < laySize ? [...current, card] : current,
      )
    },
    [laySize],
  )

  if (shell.refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state || !frame) return <p className="table-loading">Henter bordet…</p>

  const { view, seats } = state
  const play = view.play
  const finished = state.status === "finished"
  const next = finished ? (state.next_path ?? null) : null
  const goNext = () => next && window.location.assign(next)
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex) => (seat === me ? "Dig" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const leave = shell.leave
  const names: Names = { me, names: seats.map((seat) => seat.name) }
  const said = lastSaid(view.bidding.history)
  const choose: Choose = (action, ...data) => {
    setSentAt(state.version)
    send(action, (data[0] ?? {}) as ClientIntents[typeof action])
  }
  const sent = sentAt === state.version
  const discarding = view.choices.discard
  const fordaektOffered = view.choices.fordaekt.length > 0
  const pickingFordaekt = choosingFordaekt && fordaektOffered && !sent
  const faceDown = fordaektWaiting(play)
  const playing = view.phase === "playing" || view.phase === "complete"
  // Once the play starts (at a sol-melding already while the kitty goes round) the tags show roles, not what was said.
  const tagSaid = (seat: SeatIndex) => (seat === me ? undefined : (playing || solPlay(view)) && play ? undefined : said.get(seat))

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
        receivedAt={received}
        timer={state.timer}
        said={chat.bubbles.get(seat.seat)}
      />
    )
  }
  const opponent = (position: Exclude<Position, "south">) => {
    const seat = seatAt(position)
    if (!seat) return null
    const open = openHandAt(view, seat.seat)
    if (open) return <OpenHand anchor={seatEls.ref(seat.seat)} position={position} cards={open} label={openHandLabel(seat.seat, open.length, names)} />
    const revealed = revealedHand(state.vis_kort, seat.seat)
    if (revealed) return <OpenHand anchor={seatEls.ref(seat.seat)} position={position} cards={revealed} label={`Kort hos ${seat.name}:`} />
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
                {play && play.turned.length > 0 && (view.phase === "turning" || view.phase === "banking" || view.phase === "discarding") ? (
                  <VipKitty turned={play.turned} hidden={view.kitty_count - play.turned.length} taken={play.vip_card} />
                ) : view.kitty_count > 0 && (
                  <div className="esmakker-kitty" role="img" aria-label={`Katten: ${view.kitty_count} kort`}>
                    {Array.from({ length: view.kitty_count }, (_, index) => (
                      <CardBack key={index} size="sm" />
                    ))}
                  </div>
                )}
                {play ? (
                  <DeclarationCentre
                    view={view}
                    names={names}
                    selected={discardSelection.length}
                    sent={sent}
                    onDiscard={() => choose("discard", { cards: discardSelection })}
                    onKeep={() => choose("discard", { cards: [] })}
                  >
                    {view.phase === "banking" && state.bank_window && (
                      <BankWindowBox window={state.bank_window} receivedAt={received} offered={view.choices.bank} banks={play.banks.length} factor={state.rules.points.bank} sent={sent} onBank={() => choose("bank")} />
                    )}
                  </DeclarationCentre>
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
              <>
                <Contract view={view} />
                <BanksCorner banks={play.banks} names={names} factor={state.rules.points.bank} />
              </>
            ) : (
              <span className="table-corner table-corner-left">
                Runde {state.runde} af {state.runder}
              </span>
            )}
            <span className="table-corner table-corner-right">{play && playing ? <StikCorner view={view} names={names} /> : `Giver: ${nameOf(view.dealer)}`}</span>
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

          <TableToasts notice={shell.notice} warning={shell.warning} />

          {view.phase === "complete" && view.result && (
            <div className="table-overlay-host">
              {finished ? (
                <FinalOverview state={state} names={names} onNext={goNext} onLeave={leave} />
              ) : (
                <RundeResultCard result={view.result} names={names} runde={state.runde} totals={state.score.totals} onNext={() => send("next_runde", {})} />
              )}
            </div>
          )}
        </div>

        <EsmakkerSidePanel
          state={state}
          connected={shell.connected}
          nameOf={nameOf}
          names={names}
          chat={chat}
          userId={userId}
          onLeave={leave}
          onChoose={choose}
          sent={sent}
          choosingFordaekt={pickingFordaekt}
          onToggleFordaekt={() => setChoosingFordaekt((current) => !current)}
          visKort={
            state.vis_kort && (
              <VisKortBox visKort={state.vis_kort} log={thoughts} nameOf={nameOf} lineOf={esmakkerThoughtLine} onSwitch={(on) => send("vis_kort", { on })} />
            )
          }
        />

        <LeaveForm formRef={shell.leaveForm} next={next} departurePath={departurePath} />
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
      {role && <span className={`esmakker-role is-melder${role.endsWith("væltet") ? " is-vaeltet" : ""}`}>{role}</span>}
      {said && <span className="esmakker-said">{said}</span>}
      {stik && <span className="esmakker-said">{stik}</span>}
    </>
  )
}

type ChoiceAction = "bid" | "pas" | "det_kan_jeg_selv" | "gaa_med" | "claim_jernhaand" | "choose_trump" | "call_ace" | "turn_card" | "accept_trump" | "bank" | "discard"
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

/** Under the contract at vip: who banked and the doubling (×2/×4), in sight for the rest of the runde. */
function BanksCorner({ banks, names, factor }: { banks: SeatIndex[]; names: Names; factor: number }) {
  if (banks.length === 0) return null
  const lines = bankLines(banks, names, factor)
  return (
    <span className="table-corner esmakker-banks-corner" title={lines.join(" · ")} aria-label={lines.join(", ")}>
      <strong>Bank {bankFactor(banks.length, factor)}</strong>
      <small>{banks.map((seat) => (seat === names.me ? "dig" : (names.names[seat] ?? ""))).join(", ")}</small>
    </span>
  )
}

/**
 * Vip's bank window in the middle of the frame, the same for everyone: the
 * seconds left counting down from when the state arrived (the server
 * closes the window), a bar, who banked, and "Bank" for the seats the
 * server offers it.
 */
function BankWindowBox(props: { window: BankWindow; receivedAt: number; offered: boolean; banks: number; factor: number; sent: boolean; onBank: () => void }) {
  const { window, receivedAt, offered, banks, factor, sent, onBank } = props
  const now = useNow(true)
  const left = bankSecondsLeft(window, receivedAt, now) ?? 0
  return (
    <div className="esmakker-bank" role="group" aria-label="Bank i bordet">
      <p className="esmakker-bank-clock" aria-live="off">
        <span>Bank</span>
        <strong>{countdownSeconds(left)}</strong>
        <span>sek.</span>
      </p>
      <div className="esmakker-bank-bar" aria-hidden="true">
        <span style={{ width: `${countdownFraction(left, window) * 100}%` }} />
      </div>
      {offered && (
        <button type="button" className="table-btn table-btn-primary esmakker-bank-button" disabled={sent || left <= 0} onClick={onBank}>
          {bankButtonLabel(banks, factor)}
        </button>
      )}
    </div>
  )
}

/**
 * The frame's right corner during the stik: the stik per side once you
 * know the sides, otherwise yours; at a sol-melding each sol player's stik
 * and who is væltet.
 */
function StikCorner({ view, names }: { view: EsmakkerView; names: Names }) {
  const play = view.play
  if (!play) return null
  const sol = solPlay(view)
  if (sol) {
    return (
      <span className="esmakker-sol-status" aria-label="Sol-spillerne">
        <small>{solAllowedText(sol.most_stik)}</small>
        {solStatus(sol, names).map((line) => (
          <span key={line.seat} className={line.vaeltet ? "is-vaeltet" : undefined}>
            {line.name}: {stikLabel(line.stik)}
            {line.vaeltet && " · væltet"}
          </span>
        ))}
      </span>
    )
  }
  if (play.side_stik) return <>{`Melder ${play.side_stik.melder} · Mod ${play.side_stik.modspillere}`}</>
  return <>{`Dine stik: ${play.tricks_won[names.me] ?? 0}`}</>
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

/**
 * The middle of the frame while the melder declares; she lays up to three
 * of her own cards away from here, before she sees the kitty, and the same
 * number of kitty cards then come into her hand; or she keeps her cards.
 * At a sol-melding each seat in turn exchanges with what is left of the
 * kitty the same way. At vip the bank window (`children`) shows here.
 */
function DeclarationCentre(props: { view: EsmakkerView; names: Names; selected: number; sent: boolean; onDiscard: () => void; onKeep: () => void; children?: ReactNode }) {
  const { view, names, selected, sent, onDiscard, onKeep, children } = props
  const text = declarationText(view, names)
  if (!text) return null
  const sol = solPlay(view)
  const outcome = view.bidding.outcome
  const size = discardSize(view)
  return (
    <div className={`esmakker-bidding is-done${sol && view.choices.discard ? " has-exchange" : ""}${view.phase === "banking" ? " is-banking" : ""}`} aria-live="polite">
      <p className="esmakker-bidding-label">{text.headline}</p>
      <p className="esmakker-bidding-melding">{sol && outcome?.kind === "melder" ? solPlayersText(sol, outcome.melding, names) : contractText(view)}</p>
      <p className="esmakker-bidding-detail">{text.detail}</p>
      {children}
      {view.choices.discard && (
        <div className="esmakker-discard-buttons">
          <button type="button" className="table-btn table-btn-primary esmakker-discard" disabled={sent || selected === 0 || selected > size} onClick={onDiscard}>
            {discardButtonText(selected, size)}
          </button>
          <button type="button" className="table-btn esmakker-discard" disabled={sent} onClick={onKeep}>
            Byt ingen: behold mine kort
          </button>
        </div>
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
      {choices.discard && (
        <p className="esmakker-box-title">
          Tryk på op til {discardSize(view)} kort i hånden, og læg dem væk. Ingen ser dem, og du ser ikke katten først. Bagefter får du lige så mange kort fra katten.
        </p>
      )}
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
  const tone = result.gik_hjem ? " is-home" : " is-bet"
  const side = result.kind === "sol" ? (result.sol?.players ?? []) : [result.melder, result.esmakker]
  return (
    <div className={`table-overlay esmakker-result${tone}`} role="dialog" aria-labelledby="esmakker-result-title">
      <p className="esmakker-bidding-label">Runde {runde} er slut</p>
      <h2 id="esmakker-result-title">{headline}</h2>
      <p className="table-overlay-note">{detail}</p>
      <ul className="esmakker-result-stik">
        {runderPointsLine(result, names.names).map(({ seat, name, points }) => (
          <li key={seat} className={side.includes(seat) ? "is-side" : undefined}>
            <span>{seat === names.me ? "Dig" : name}</span>
            <small>{stikLabel(result.tricks_won[seat] ?? 0)}</small>
            <strong className={(result.points[seat] ?? 0) > 0 ? "is-won" : (result.points[seat] ?? 0) < 0 ? "is-lost" : undefined}>{points}</strong>
          </li>
        ))}
      </ul>
      {totals && (
        <p className="table-overlay-note esmakker-result-totals">
          I alt: {totals.map((total, seat) => `${seat === names.me ? "dig" : (names.names[seat] ?? "")} ${totalPoints(total)}`).join(" · ")}
        </p>
      )}
      <p className="table-overlay-note">Næste runde starter om lidt.</p>
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
              <td>{row.stik === "–" ? "" : /^\d+$/.test(row.stik) ? stikLabel(Number(row.stik)) : row.stik}</td>
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
          <strong>Du har jernhånd!</strong>
          <span>Ingen billedkort, esser eller jokere. Tryk her, så gives kortene om.</span>
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

/**
 * Es-makker's panel in the shared frame (TablePanel): under Spil each seat
 * with its points and role in the runde, your choices on your turn and the
 * meldinger or runder so far; the stillingsark under Stilling, the bord's
 * rules under Regler. On a narrow screen a bar under the felt.
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
  /** "Vis kort" (VisKortBox), for an admin alone with bots. */
  visKort: ReactNode
}) {
  const { state, connected, nameOf, names, chat, userId, onLeave, onChoose, sent, choosingFordaekt, onToggleFordaekt, visKort } = props
  const { view, seats } = state
  const [scoreModal, setScoreModal] = useState(false)

  const role = (seat: SeatIndex): ReactNode => (seat === view.dealer ? "Giver" : seat === view.forhand ? "Forhånd" : " ")

  return (
    <>
      <TablePanel
        info={`Es-makker · ${state.table_kind === "practice" ? "Øvebord" : `Bord ${state.table_id}`} · Runde ${state.runde} af ${state.runder}`}
        connected={connected}
        chat={chat}
        userId={userId}
        bodyClass={hasChoices(view.choices) ? "has-choices" : undefined}
        spil={
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
            {contractSentence(view, names) && <p className="esmakker-contract-line">{contractSentence(view, names)}</p>}
            {hasBiddingChoices(view.choices) && <BiddingBox choices={view.choices} melding={view.bidding.melding} pahaengOrder={state.rules.pahaeng_order} sent={sent} onChoose={onChoose} />}
            {hasDeclarationChoices(view.choices) && <DeclarationBox view={view} sent={sent} onChoose={onChoose} />}
            {view.choices.fordaekt.length > 0 && view.play?.called_ace && (
              <FordaektBox calledAce={view.play.called_ace} choosing={choosingFordaekt} sent={sent} onToggle={onToggleFordaekt} />
            )}
            {view.play ? <RunderTable results={state.score.results} names={seats.map((seat) => seat.name)} me={view.seat} /> : <BiddingHistory bidding={view.bidding} nameOf={nameOf} />}
          </>
        }
        visKort={visKort}
        stilling={
          <div className="table-panel-score esmakker-panel-score">
            <p>Point vindes og tabes mellem spillerne; summen er altid 0. Højeste total vinder.</p>
            <EsmakkerScoreSheet results={state.score.results} names={seats.map((seat) => seat.name)} totals={state.score.totals} leaders={state.score.leaders} me={view.seat} />
            <EsmakkerLookupTable points={state.rules.points} />
          </div>
        }
        regler={
          <div className="table-panel-rules esmakker-panel-rules">
            <EsmakkerRulesSummary rules={state.rules} runder={state.runder} />
          </div>
        }
        regelbogPath="/regelbog#esmakker"
        status={status(view, names)}
        onShowScore={() => setScoreModal(true)}
        finished={state.status === "finished"}
        practice={state.table_kind === "practice"}
        onLeave={onLeave}
      />
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
    </>
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
