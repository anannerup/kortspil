import type { LobbySeat, LobbyTable } from "./messages"
import { tablePaths } from "./messages"
import { PostForm } from "./PostForm"

export const SEAT_COUNT = 4

export const takenSeats = (table: LobbyTable) => table.seats.filter((seat) => seat.name !== null).length

export function statusLabel(table: LobbyTable): string {
  if (table.status === "playing") return "I gang"
  if (table.status === "closed") return "Lukket"
  const held = table.reserved > 0 ? `, ${table.reserved} holdt til puf` : ""
  return `Venter på spillere (${takenSeats(table)}/${SEAT_COUNT}${held})`
}

/**
 * A table's four seats: who sits where, and a "Sæt dig her" button on each
 * free seat while the table waits. Every seat's button submits one sit
 * form, which holds the password field at a password table the user does
 * not sit at yet. The server decides whether it is allowed. (At the bord
 * itself the seats are TableSetup's.)
 */
export function Seats({ table, userId }: { table: LobbyTable; userId: number }) {
  const seated = table.seats.some((seat) => seat.user_id === userId)
  const canSit = table.status === "waiting" && takenSeats(table) + table.reserved < SEAT_COUNT
  const needsPassword = canSit && table.kind === "password" && !seated
  const sitForm = `sit-${table.id}`

  return (
    <>
      {canSit && (
        <PostForm action={tablePaths(table.path).seat} id={sitForm} className="lobby-sit">
          {needsPassword && (
            <div className="field">
              <label htmlFor={`${sitForm}-password`}>Adgangskode</label>
              <input id={`${sitForm}-password`} type="password" name="password" autoComplete="off" required />
            </div>
          )}
        </PostForm>
      )}
      <ol className="lobby-seats">
        {table.seats.map((seat) => (
          <li key={seat.seat} className={seat.name === null ? "lobby-seat lobby-seat-free" : "lobby-seat"}>
            <SeatContent table={table} seat={seat} userId={userId} sitForm={sitForm} />
          </li>
        ))}
      </ol>
    </>
  )
}

function SeatContent(props: { table: LobbyTable; seat: LobbySeat; userId: number; sitForm: string }) {
  const { table, seat, userId, sitForm } = props

  if (seat.name !== null) {
    const notes = [seat.user_id === table.host_id && "vært", seat.user_id === userId && "dig", seat.bot && "bot"].filter(Boolean)
    return (
      <span className="lobby-seat-name">
        {seat.name}
        {notes.length > 0 && <span className="lobby-seat-note"> ({notes.join(", ")})</span>}
      </span>
    )
  }
  if (table.status !== "waiting") return <span className="lobby-seat-note">Ledig</span>

  return (
    <button type="submit" form={sitForm} name="position" value={seat.seat} className="btn btn-primary">
      Sæt dig her
    </button>
  )
}
