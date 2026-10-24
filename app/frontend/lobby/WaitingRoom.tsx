import { useEffect } from "react"
import { rulesSummary } from "~/table/texts"
import { tablePaths, type LobbyTable } from "./messages"
import { PostForm } from "./PostForm"
import { SEAT_COUNT, Seats, statusLabel, takenSeats } from "./Seats"
import { useLobbyTables } from "./useLobbyTables"
import "./lobby.css"

const LOBBY_PATH = "/"

/**
 * A bord's own page before the spil starts: its rules and seats, live from
 * LobbyChannel. Anyone may take a free seat; the seated can stand up and the
 * vært starts once every seat is taken. When the spil starts the page
 * reloads into the table; when the bord closes it goes back to the lobby.
 */
export function WaitingRoom({ initialTable, userId }: { initialTable: LobbyTable; userId: number }) {
  const { tables, live } = useLobbyTables([initialTable])
  const table = tables.find((listed) => listed.id === initialTable.id)

  useEffect(() => {
    if (!live) return
    if (!table) window.location.assign(LOBBY_PATH)
    else if (table.status !== "waiting") window.location.reload()
  }, [live, table])

  if (!table) return <p>Bordet er lukket.</p>

  const paths = tablePaths(table.id)
  const seated = table.seats.some((seat) => seat.user_id === userId)
  const isHost = table.host_id === userId
  const missing = SEAT_COUNT - takenSeats(table)

  return (
    <div className="lobby lobby-waiting">
      <h1>Bord {table.id}</h1>
      <p>
        Vært: {table.host} · <span className="lobby-status">{statusLabel(table)}</span>
      </p>
      <p className="lobby-rules-summary">Regler: {rulesSummary(table.rules)}</p>

      <Seats table={table} userId={userId} />

      <div className="lobby-actions">
        {isHost && (
          <PostForm action={paths.start}>
            <button type="submit" disabled={missing > 0}>
              Start spillet
            </button>
          </PostForm>
        )}
        {seated && (
          <PostForm action={paths.departure}>
            <button type="submit">Rejs dig</button>
          </PostForm>
        )}
      </div>
      {missing > 0 && <p>{isHost ? `Du kan starte, når alle pladser er besat. Der mangler ${missing}.` : `Værten starter, når alle pladser er besat. Der mangler ${missing}.`}</p>}
      {!seated && <p>Vælg en ledig plads for at sætte dig.</p>}
      <p>
        Send linket til bordet til dem, du vil spille med: <a href={paths.table}>{window.location.origin + paths.table}</a>
      </p>
    </div>
  )
}
