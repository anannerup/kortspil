import { Fragment, useCallback, useEffect, useRef, useState } from "react"
import { CardBack } from "~/cards"
import { csrfToken } from "~/lobby/PostForm"
import { tablePaths, type BotLevel, type Friend, type LobbySeat, type LobbyTable } from "~/lobby/messages"
import { sendTableAction } from "~/lobby/tableActions"
import { useWaitingTable } from "~/lobby/useLobbyTables"
import type { SeatIndex } from "./messages"
import { SeatTag } from "./SeatTag"
import { canStart, centreLine, GAME_NAMES, isEmpty, lengthLabel, seatAt, seatOf, seatRoles } from "./setup"
import { DEFAULT_BOT_LEVEL, SetupPanel, type SetupActions } from "./SetupPanel"
import { subscribeToTable, type TableSubscription } from "./tableSubscription"
import { botKind } from "./texts"
import { POSITIONS, type Position } from "./Trick"
import { useTableChat, type TableChat } from "./useTableChat"
import "./table.css"
import "./setup.css"

const LOBBY_PATH = "/"
/** Name tags before the spil: no clock runs. */
const NO_TIMER = { warning: 30, limit: 60 }

/**
 * A bord before its spil: the same table as during play (green felt, the
 * framed middle with the name tags on its edges), with each seat at its
 * place around it, and the bord's settings in a panel on the right, as
 * during play. Nothing is stored yet: the bord lives in the lobby (in the
 * server's memory) until the vært starts it, which they can once every
 * seat holds a human or a bot. The game was chosen in the lobby.
 *
 * Anyone who may sit here takes a free seat at the table (with the
 * password at a password table). The vært changes the rules and the type,
 * puts bots in empty seats (at the level they pick: Let, Mellem or Svær)
 * and takes them out, kicks players, and nudges
 * friends (puf); the others see the same settings, read-only. Changes are
 * sent as JSON (sendTableAction) and come back live to everyone at the
 * bord on LobbyChannel. When the spil starts the page goes to the stored
 * table; when the bord closes it goes back to the lobby. A practice bord
 * is the same page with its three bots fixed.
 */
export function TableSetup(props: { initialTable: LobbyTable; userId: number; departurePath: string; notice: string | null; friends: Friend[] }) {
  const { initialTable, userId, departurePath, notice, friends } = props
  const { table, setTable, live } = useWaitingTable(initialTable)
  const me = seatOf(table, userId)
  const seated = me !== null
  const isHost = table.host_id === userId
  const practice = table.kind === "practice"
  const kicked = useKicked(seated)
  const [message, setMessage] = useState<string | null>(notice)
  const [busy, setBusy] = useState(false)
  const [password, setPassword] = useState("")
  // The level the vært picked for a bot in each free seat, before adding it.
  const [newBotLevels, setNewBotLevels] = useState<Partial<Record<SeatIndex, BotLevel>>>({})
  const chat = useSetupChat(table.id, userId, seated && !practice)
  const leaveForm = useRef<HTMLFormElement | null>(null)
  const paths = tablePaths(initialTable.path)

  useEffect(() => {
    if (!live) return
    if (table.status === "closed") window.location.assign(LOBBY_PATH)
    else if (table.status === "playing") window.location.assign(table.path)
  }, [live, table.status, table.path])

  useEffect(() => {
    if (!message) return
    const timer = setTimeout(() => setMessage(null), 4000)
    return () => clearTimeout(timer)
  }, [message])

  const send = useCallback(
    async (path: string, fields: Record<string, string>, method?: "patch" | "delete") => {
      setBusy(true)
      const result = await sendTableAction(path, fields, method)
      setBusy(false)
      if ("error" in result) {
        setMessage(result.error)
        return false
      }
      setTable(result.table)
      if (result.table.status === "playing") window.location.assign(result.table.path)
      return true
    },
    [setTable],
  )

  const actions: SetupActions = {
    busy,
    sit: (seat) => send(paths.seat, { position: String(seat), ...(password ? { password } : {}) }),
    addBot: (seat, level) => send(paths.bot, { position: String(seat), level }),
    newBotLevel: (seat) => newBotLevels[seat] ?? DEFAULT_BOT_LEVEL,
    chooseNewBotLevel: (seat, level) => setNewBotLevels((levels) => ({ ...levels, [seat]: level })),
    setBotLevel: (seat, level) => send(paths.bot, { position: String(seat), level }, "patch"),
    removeBot: (seat) => send(paths.bot, { position: String(seat) }, "delete"),
    kick: (seat) => send(paths.kick, { position: String(seat) }),
    saveSettings: (fields) => send(paths.settings, fields, "patch"),
    nudge: (friendId) => send(paths.nudges, { friend_id: String(friendId) }),
    withdrawNudge: (nudgeId) => send(`${paths.nudges}/${nudgeId}`, {}, "delete"),
    leave: () => {
      kicked.standingUp()
      leaveForm.current?.requestSubmit()
    },
  }

  if (table.status === "closed") return <p className="table-loading">Bordet er lukket.</p>

  const needsPassword = !seated && table.kind === "password"
  const sitLabel = seated ? "Flyt hertil" : "Sæt dig her"

  const tag = (position: Position) => {
    const seat = seatAt(table, position, me)
    if (!seat) return null
    if (isEmpty(seat)) return <span className={`table-tag table-tag-${position} setup-tag-free`}>Ledig</span>
    return (
      <SeatTag
        info={{ seat: seat.seat, name: seat.name ?? "", bot: seat.bot, bot_level: seat.bot_level, took_over_from: null, frakoblet: false, seconds_left: null }}
        edge={position}
        label={seat.seat === me ? "Dig" : (seat.name ?? "")}
        isMe={seat.seat === me}
        active={false}
        receivedAt={0}
        timer={NO_TIMER}
        said={chat.bubbles.get(seat.seat)}
      />
    )
  }

  const chair = (position: Position) => {
    const seat = seatAt(table, position, me)
    if (!seat) return null
    return (
      <Chair
        key={position}
        seat={seat}
        position={position}
        roles={seatRoles(seat, table, userId).filter((role) => role !== "bot")}
        sitLabel={sitLabel}
        canSit={!practice && (!needsPassword || password !== "")}
        isHost={isHost && !practice}
        botsAllowed={table.bots_allowed}
        actions={actions}
      />
    )
  }

  return (
    <section className="table-page table-setup" aria-label={table.name}>
      <div className="table-felt setup-felt">
        {chair("north")}
        {chair("west")}
        {chair("east")}

        <div className="table-frame">
          {POSITIONS.map((position) => (
            <Fragment key={position}>{tag(position)}</Fragment>
          ))}
          <div className="setup-centre">
            <div className="setup-deck" aria-hidden="true">
              <CardBack size="sm" />
              <CardBack size="sm" />
              <CardBack size="sm" />
            </div>
            <p className="setup-game">{GAME_NAMES[table.game]}</p>
            <p className="setup-line">{centreLine(table)}</p>
            {needsPassword && (
              <label className="setup-password">
                <span>Adgangskode</span>
                <input type="password" autoComplete="off" value={password} onChange={(event) => setPassword(event.target.value)} />
              </label>
            )}
            {isHost ? (
              <button type="button" className="table-btn table-btn-primary table-btn-xl setup-start" disabled={!canStart(table) || busy} onClick={() => send(paths.start, {})}>
                Start spil
              </button>
            ) : (
              seated && <p className="setup-wait">{table.host} starter spillet</p>
            )}
          </div>
          <div className="setup-corners">
            <span className="table-corner table-corner-left">{table.name}</span>
            <span className="table-corner table-corner-right">{lengthLabel(table)}</span>
          </div>
        </div>

        {chair("south")}

        {kicked.current && !seated && (
          <p className="table-toast table-toast-warning" role="alert">
            Værten har fjernet dig fra bordet.
          </p>
        )}
        <p className={`table-toast${message ? "" : " is-hidden"}`} role="alert">
          {message}
        </p>
      </div>

      <SetupPanel table={table} userId={userId} seated={seated} isHost={isHost} actions={actions} chat={chat} friends={friends} />

      <form ref={leaveForm} method="post" action={departurePath} hidden>
        <input type="hidden" name="authenticity_token" value={csrfToken()} />
      </form>
    </section>
  )
}

/**
 * A seat at its place around the table: who sits there, or a free seat
 * that invites you to sit down and the vært to put a bot there. Each seat
 * has its own cell around the frame (setup.css), so it never covers the
 * frame or its name tag; on narrow screens the side seats get compact.
 */
function Chair(props: { seat: LobbySeat; position: Position; roles: string[]; sitLabel: string; canSit: boolean; isHost: boolean; botsAllowed: boolean; actions: SetupActions }) {
  const { seat, position, roles, sitLabel, canSit, isHost, botsAllowed, actions } = props
  if (isEmpty(seat)) {
    return (
      <div className={`setup-chair setup-chair-${position} is-free`}>
        <span className="setup-chair-avatar" aria-hidden="true">
          +
        </span>
        <span className="setup-chair-name">
          <span className="setup-long">Ledig plads</span>
          <span className="setup-short">Ledig</span>
        </span>
        <div className="setup-chair-actions">
          <button type="button" className="setup-chip setup-chip-primary" disabled={!canSit || actions.busy} onClick={() => actions.sit(seat.seat)}>
            {sitLabel}
          </button>
          {isHost && botsAllowed && (
            <button type="button" className="setup-chip" aria-label="Sæt en bot her" disabled={actions.busy} onClick={() => actions.addBot(seat.seat, actions.newBotLevel(seat.seat))}>
              <span className="setup-long">Sæt en bot her</span>
              <span className="setup-short">+ Bot</span>
            </button>
          )}
        </div>
      </div>
    )
  }
  return (
    <div className={`setup-chair setup-chair-${position}${seat.bot ? " is-bot" : ""}`}>
      <span className="setup-chair-avatar" aria-hidden="true">
        {seat.bot ? "🤖" : (seat.name ?? "?").charAt(0).toUpperCase()}
      </span>
      <span className="setup-chair-name">{seat.name}</span>
      {seat.bot && <span className="setup-chair-roles">{botKind(seat.bot_level)}</span>}
      {roles.length > 0 && <span className="setup-chair-roles">{roles.join(" · ")}</span>}
    </div>
  )
}

/**
 * The table chat before the spil, for the seated: it subscribes to the
 * table's channel only for the chat, which carries over into the spil.
 * New messages show as speech bubbles at the author's tag, as in play.
 */
function useSetupChat(tableId: number | string, userId: number, enabled: boolean): TableChat {
  const subscription = useRef<TableSubscription | null>(null)
  const chat = useTableChat(
    userId,
    useCallback((text: string) => subscription.current?.send("chat", { text }), []),
  )
  const { receive } = chat

  useEffect(() => {
    if (!enabled) return
    subscription.current = subscribeToTable(tableId, { onMessage: receive, onConnectionChange: () => {}, onRejected: () => {} })
    return () => {
      subscription.current?.close()
      subscription.current = null
    }
  }, [tableId, enabled, receive])

  return chat
}

/**
 * Whether the user was seated and lost the seat without standing up
 * themself: the vært kicked them. `standingUp` marks the user's own
 * leaving, whose redirect may lag behind the update.
 */
function useKicked(seated: boolean): { current: boolean; standingUp: () => void } {
  const wasSeated = useRef(seated)
  const leaving = useRef(false)
  const [kicked, setKicked] = useState(false)

  useEffect(() => {
    if (wasSeated.current && !seated && !leaving.current) setKicked(true)
    if (seated) setKicked(false)
    wasSeated.current = seated
  }, [seated])

  return {
    current: kicked,
    standingUp: () => {
      leaving.current = true
    },
  }
}
