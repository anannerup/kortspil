import { memo, type ReactNode } from "react"
import { formatClock } from "~/app/countdown"
import type { ChatEntry, SeatIndex, SeatInfo, TurnTimer } from "./messages"
import { BOT_LEVEL_NAMES, botKind } from "./texts"
import type { Position } from "./Trick"
import { secondsLeft, useNow } from "./turnTimer"

/**
 * A name tag on the edge of the stik, with the turn timer: a bar that runs
 * down while the server has a clock for the seat, red from the warning, a
 * countdown for a frakoblet player, a bot's level ("Bot 2 · Svær") and
 * "Bot · Let (overtog fra …)". Only a tag
 * with a running clock ticks, so the clock never renders the rest of the
 * table.
 */
export const SeatTag = memo(function SeatTag(props: {
  info: SeatInfo | undefined
  edge: Position
  /** The name, or "Dig"; es-makker adds the kortgiver and forhånd markers. */
  label: ReactNode
  isMe: boolean
  active: boolean
  /** The game's own marker class on the tag (hjerterfri's bytte: "is-passed" / "is-choosing"). */
  marker?: string | null
  receivedAt: number
  timer: TurnTimer
  said: ChatEntry | undefined
}) {
  const { info, edge, label, isMe, active, marker, receivedAt, timer, said } = props
  const now = useNow(info?.seconds_left != null)
  const left = secondsLeft(info, receivedAt, now)
  const away = info?.frakoblet ?? false
  const classes = [
    "table-tag",
    `table-tag-${edge}`,
    active ? "is-active" : "",
    marker ?? "",
    away ? "is-away" : "",
    left !== null && left <= timer.limit - timer.warning ? "is-warning" : "",
  ]
  return (
    <>
      <span className={classes.filter(Boolean).join(" ")}>
        {info?.took_over_from && !isMe ? `${botKind(info.bot_level)} (overtog fra ${info.took_over_from})` : label}
        {!isMe && info?.bot && !info.took_over_from && <span className="table-tag-bot"> · {info.bot_level ? BOT_LEVEL_NAMES[info.bot_level] : "bot"}</span>}
        {away && left !== null && <span className="table-tag-away"> · frakoblet {formatClock(left)}</span>}
        {left !== null && <span className="table-tag-timer" aria-hidden="true" style={{ transform: `scaleX(${left / timer.limit})` }} />}
      </span>
      {said && (
        <span key={said.id} className={`table-bubble table-bubble-${edge}`} aria-hidden="true">
          {said.text}
        </span>
      )}
    </>
  )
})

/**
 * The status line. While we wait for a seat that is frakoblet or past its
 * warning, it counts down; only then does it tick.
 */
export const StatusLine = memo(function StatusLine(props: {
  state: { view: { to_act: SeatIndex | null; seat: SeatIndex }; seats: SeatInfo[]; timer: TurnTimer }
  receivedAt: number
  text: ReactNode
  nameOf: (seat: SeatIndex | null) => string
}) {
  const { state, receivedAt, text, nameOf } = props
  const { view, seats, timer } = state
  const waitedFor = view.to_act !== null && view.to_act !== view.seat ? view.to_act : null
  const seat = waitedFor === null ? undefined : seats[waitedFor]
  const now = useNow(seat?.seconds_left != null)
  const left = secondsLeft(seat, receivedAt, now)
  if (left !== null && (seat?.frakoblet || left <= timer.limit - timer.warning)) return <>{`Venter på ${nameOf(waitedFor)}… ${formatClock(left)}`}</>
  return <>{text}</>
})
