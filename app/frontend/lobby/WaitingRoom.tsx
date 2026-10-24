import { useEffect, useRef, useState } from "react"
import { WaitingRoomChat } from "~/table/Chat"
import { rulesSummary } from "~/table/texts"
import { tablePaths, type LobbyTable } from "./messages"
import { PostForm } from "./PostForm"
import { SEAT_COUNT, Seats, statusLabel, takenSeats } from "./Seats"
import { TableKindPill } from "./TableKindPill"
import { TableSettingsFields } from "./TableSettingsFields"
import { useWaitingTable } from "./useLobbyTables"
import "./lobby.css"

const LOBBY_PATH = "/"

/**
 * A bord's own page before the spil starts: its type, rules and seats,
 * live from LobbyChannel (this table's own stream, so private tables work
 * too). Anyone may take a free seat (with the password at a password
 * table); the seated can stand up. The vært kicks players, puts bots in
 * empty seats and takes them out, changes the rules and the table type,
 * and starts once every seat is taken. The seated can chat (the same
 * table chat as during the spil). When the spil starts the page
 * reloads into the table; when the bord closes it goes back to the lobby.
 */
export function WaitingRoom({ initialTable, userId }: { initialTable: LobbyTable; userId: number }) {
  const { table, live } = useWaitingTable(initialTable)
  const seated = table.seats.some((seat) => seat.user_id === userId)
  const kicked = useKicked(seated)

  useEffect(() => {
    if (!live) return
    if (table.status === "closed") window.location.assign(LOBBY_PATH)
    else if (table.status !== "waiting") window.location.reload()
  }, [live, table.status])

  if (table.status === "closed") return <p>Bordet er lukket.</p>

  const paths = tablePaths(table.id)
  const isHost = table.host_id === userId
  const missing = SEAT_COUNT - takenSeats(table)
  const link = window.location.origin + paths.table

  return (
    <div className="lobby lobby-waiting">
      <div className="page-header">
        <h1 className="lobby-title">
          Bord {table.id} <TableKindPill kind={table.kind} />
        </h1>
        <p className="lead">
          Vært: {table.host} · <span className="lobby-status">{statusLabel(table)}</span>
        </p>
      </div>

      {kicked.current && !seated && (
        <p className="flash flash-alert" role="alert">
          Værten har fjernet dig fra bordet. <a href={LOBBY_PATH}>Til lobbyen</a>
        </p>
      )}

      <section className="panel">
        <h2>Pladser</h2>
        <Seats table={table} userId={userId} hostControls={isHost} />
        {missing > 0 && (
          <p className="hint">
            {isHost
              ? `Du kan starte, når alle pladser er besat. Der mangler ${missing}. Sæt bots på de tomme pladser, hvis I er færre end fire.`
              : `Værten starter, når alle pladser er besat. Der mangler ${missing}.`}
          </p>
        )}
        {!seated && <p className="hint">Vælg en ledig plads for at sætte dig.</p>}
        <div className="lobby-actions">
          {isHost && (
            <PostForm action={paths.start}>
              <button type="submit" className="btn btn-primary" disabled={missing > 0}>
                Start spillet
              </button>
            </PostForm>
          )}
          {seated && (
            <PostForm action={paths.departure} onSubmit={kicked.standingUp}>
              <button type="submit" className="btn btn-secondary">
                Rejs dig
              </button>
            </PostForm>
          )}
        </div>
      </section>

      {seated && (
        <section className="panel">
          <h2>Inviter</h2>
          <p className="hint">{INVITE_HINTS[table.kind]}</p>
          <CopyLink link={link} />
        </section>
      )}

      {isHost ? (
        <section className="panel">
          <h2>Indstillinger</h2>
          <p className="hint">Kun du som vært kan ændre dem, og kun indtil spillet starter.</p>
          {/* Keyed on the stored settings, so the form shows them again after a save. */}
          <PostForm key={JSON.stringify([table.kind, table.rules])} action={paths.settings} method="patch" className="lobby-rules">
            <TableSettingsFields rules={table.rules} kind={table.kind} hasPassword={table.kind === "password"} />
            <button type="submit" className="btn btn-primary">
              Gem indstillinger
            </button>
          </PostForm>
        </section>
      ) : (
        <section className="panel">
          <h2>Regler</h2>
          <p className="lobby-rules-summary">{rulesSummary(table.rules)}</p>
        </section>
      )}
      {seated ? (
        <section className="panel">
          <WaitingRoomChat tableId={table.id} userId={userId} />
        </section>
      ) : (
        <p className="lobby-hint">Sæt dig på en ledig plads, så kan du også chatte med de andre ved bordet.</p>
      )}
    </div>
  )
}

const INVITE_HINTS: Record<LobbyTable["kind"], string> = {
  open: "Bordet vises i lobbyen. Send linket til dem, du vil spille med.",
  password: "Bordet vises i lobbyen med en lås. Send linket, og fortæl dem adgangskoden.",
  private: "Bordet vises ikke i lobbyen. Kun dem, der får linket, kan finde det.",
}

/** The table's link with a button that copies it. */
function CopyLink({ link }: { link: string }) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard
      ?.writeText(link)
      .then(() => setCopied(true))
      .catch(() => setCopied(false))
  }

  return (
    <div className="lobby-link">
      <a href={link}>{link}</a>
      <button type="button" className="btn btn-secondary" onClick={copy}>
        {copied ? "Kopieret" : "Kopiér link"}
      </button>
    </div>
  )
}

/**
 * Whether the user was seated and lost the seat without standing up
 * themself: the vært kicked them. `standingUp` marks the user's own "Rejs
 * dig", whose redirect may lag behind the update.
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
