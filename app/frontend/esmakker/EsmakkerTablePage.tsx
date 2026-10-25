import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react"
import { MotionConfig, motion } from "motion/react"
import { CardBack, CardFace, type CardCode } from "~/cards"
import { csrfToken } from "~/lobby/PostForm"
import { ChatLog, ChatSheet, UnreadBadge } from "~/table/Chat"
import { fanSpots, type HandSize } from "~/table/handLayout"
import type { SeatIndex, ServerMessage } from "~/table/messages"
import { SeatTag } from "~/table/SeatTag"
import { subscribeToTable, type TableSubscription } from "~/table/tableSubscription"
import { REJECTIONS } from "~/table/texts"
import { POSITIONS, type Position } from "~/table/Trick"
import { useTableChat, type TableChat } from "~/table/useTableChat"
import { biddingHeadline, historyLabel, ladderRows, lastSaid, meldingLabel, turnText, type Names } from "./bidding"
import { EsmakkerRulesSummary } from "./EsmakkerSettings"
import type { BiddingChoices, BiddingView, EsmakkerTableState } from "./messages"
import "~/table/table.css"
import "./esmakker.css"

const LOBBY_PATH = "/"
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
 */
export function EsmakkerTablePage({ tableId, departurePath, userId }: { tableId: number; departurePath: string; userId: number }) {
  const [state, setState] = useState<EsmakkerTableState | null>(null)
  const [received, setReceived] = useState(0)
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  // The version a choice was sent at: the choices wait for the next state.
  const [sentAt, setSentAt] = useState<number | null>(null)
  const subscription = useRef<TableSubscription | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)
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
      setState((current) => (current && current.game_id === next.game_id && current.version > next.version ? current : next))
      setReceived(Date.now())
    }
    subscription.current = subscribeToTable(tableId, { onMessage: handle, onConnectionChange: setConnected, onRejected: () => setRefused(true) })
    return () => subscription.current?.close()
  }, [tableId, receiveChat])

  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(null), 3500)
    return () => clearTimeout(timer)
  }, [notice])

  if (refused) return <p className="table-notice-inline">Du sidder ikke ved dette bord.</p>
  if (!state) return <p className="table-loading">Henter bordet…</p>

  const { view, seats } = state
  const me = view.seat
  const positionOf = (seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south"
  const seatAt = (position: Position) => seats.find((seat) => positionOf(seat.seat) === position)
  const nameOf = (seat: SeatIndex) => (seat === me ? "Dig" : (seats[seat]?.name ?? `Plads ${seat + 1}`))
  const leave = () => leaveForm.current?.requestSubmit()
  const names: Names = { me, names: seats.map((seat) => seat.name) }
  const said = lastSaid(view.bidding.history)
  const choose: Choose = (action, data) => {
    setSentAt(state.version)
    // Each bidding intent but the bid carries no data.
    if (action === "bid") subscription.current?.send("bid", data ?? { melding: "" })
    else subscription.current?.send(action, {})
  }

  const tag = (position: Position) => {
    const seat = seatAt(position)
    if (!seat) return null
    return (
      <SeatTag
        key={position}
        info={seat}
        edge={position}
        label={<TagLabel name={nameOf(seat.seat)} dealer={view.dealer === seat.seat} forhand={view.forhand === seat.seat} said={seat.seat === me ? undefined : said.get(seat.seat)} />}
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
    return <OpponentStack position={position} name={seat.name} count={view.card_counts[String(seat.seat)] ?? 0} />
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
            <div className="esmakker-centre">
              <div className="esmakker-kitty" role="img" aria-label={`Katten: ${view.kitty_count} kort`}>
                {Array.from({ length: view.kitty_count }, (_, index) => (
                  <CardBack key={index} size="sm" />
                ))}
              </div>
              <BiddingCentre bidding={view.bidding} names={names} />
            </div>
            <span className="table-corner table-corner-left">
              Runde {state.runde} af {state.runder}
            </span>
            <span className="table-corner table-corner-right">Giver: {nameOf(view.dealer)}</span>
          </div>

          <div className="table-hand-row">
            <EsmakkerHand key={`${state.game_id}:${state.round_number}`} cards={view.hand} />
          </div>

          <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
            {notice}
          </p>
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
          sent={sentAt === state.version}
        />

        <form ref={leaveForm} method="post" action={departurePath} hidden>
          <input type="hidden" name="authenticity_token" value={csrfToken()} />
        </form>
      </section>
    </MotionConfig>
  )
}

/** A name tag's text: the name, "giver" / "forhånd" as markers, and what the seat said last in the meldingsrunde. */
function TagLabel({ name, dealer, forhand, said }: { name: string; dealer: boolean; forhand: boolean; said: string | undefined }) {
  return (
    <>
      {name}
      {dealer && <span className="esmakker-role">giver</span>}
      {forhand && <span className="esmakker-role is-forhand">forhånd</span>}
      {said && <span className="esmakker-said">{said}</span>}
    </>
  )
}

type BiddingAction = "bid" | "pas" | "det_kan_jeg_selv" | "gaa_med" | "claim_jernhaand"
type Choose = (action: BiddingAction, data?: { melding: string }) => void

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

/** Another seat's hand: card backs at the edge of the felt. */
const OpponentStack = memo(function OpponentStack({ position, name, count }: { position: Exclude<Position, "south">; name: string; count: number }) {
  return (
    <div className={`table-stack table-stack-${position}`} aria-label={`${name}: ${count} kort`}>
      {Array.from({ length: count }, (_, index) => (
        <CardBack key={index} size="sm" />
      ))}
    </div>
  )
})

/** Your hand as the fan of the hjerterfri table (handLayout); dealt cards rise into place one after another. Nothing to play yet. */
function EsmakkerHand({ cards }: { cards: CardCode[] }) {
  const [size, sizer, row] = useHandSize()
  const spots = size ? fanSpots(cards.length, size) : []
  return (
    <div ref={row} className="table-hand" aria-label="Dine kort">
      <div ref={sizer} className="table-hand-sizer" aria-hidden="true" />
      {cards.map((code, index) => {
        const spot = spots[index]
        if (!spot) return null
        return (
          <motion.div
            key={code}
            className="table-hand-card"
            initial={{ ...spot, y: spot.y + 40, opacity: 0 }}
            animate={{ ...spot, opacity: 1 }}
            transition={{ ...CARD_MOVE, delay: index * DEAL_STAGGER }}
          >
            <CardFace code={code} />
          </motion.div>
        )
      })}
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

type Tab = "spil" | "regler" | "chat"
const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: "spil", label: "Spil", icon: "🂠" },
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
}) {
  const { state, connected, nameOf, names, chat, userId, onLeave, onChoose, sent } = props
  const { view, seats } = state
  const [tab, setTab] = useState<Tab>("spil")
  const [chatSheet, setChatSheet] = useState(false)
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
                <div key={seat.seat} className={`table-pill${view.to_act === seat.seat ? " is-active" : ""}`}>
                  <span>{nameOf(seat.seat)}</span>
                  <strong>{String(state.score.totals[seat.seat] ?? 0).replace(".", ",")}</strong>
                  <small>{role(seat.seat)}</small>
                </div>
              ))}
            </div>
            {hasChoices(view.choices) && <BiddingBox choices={view.choices} melding={view.bidding.melding} pahaengOrder={state.rules.pahaeng_order} sent={sent} onChoose={onChoose} />}
            <BiddingHistory bidding={view.bidding} nameOf={nameOf} />
          </>
        )}
        {tab === "regler" && (
          <div className="table-panel-rules esmakker-panel-rules">
            <EsmakkerRulesSummary rules={state.rules} runder={state.runder} />
          </div>
        )}
        {tab === "chat" && !narrow && <ChatLog chat={chat} userId={userId} />}
      </div>

      <p className="table-status" aria-live="polite">
        {status(view.bidding, names)}
      </p>
      <div className="table-panel-buttons">
        <button type="button" className="table-btn table-panel-chat-button" onClick={() => setChatSheet(true)}>
          Chat
          <UnreadBadge count={chat.unread} />
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
    </aside>
  )
}

const hasChoices = (choices: BiddingChoices) => choices.pas || choices.jernhaand || choices.det_kan_jeg_selv || choices.gaa_med || choices.meldinger.length > 0

/** The status line: whose turn, or how the meldingsrunde ended. */
function status(bidding: BiddingView, names: Names): string {
  const turn = turnText(bidding, names)
  if (turn) return turn
  const { headline, detail } = biddingHeadline(bidding, names)
  return detail ? `${headline}. ${detail}` : headline
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
