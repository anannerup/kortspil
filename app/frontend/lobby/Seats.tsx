import type { LobbySeat, LobbyTable } from "./messages"
import { tablePaths } from "./messages"
import { PostForm } from "./PostForm"

export const SEAT_COUNT = 4

export const takenSeats = (table: LobbyTable) => table.seats.filter((seat) => seat.name !== null).length

export function statusLabel(table: LobbyTable): string {
  if (table.status === "playing") return "I gang"
  return `Venter på spillere (${takenSeats(table)}/${SEAT_COUNT})`
}

/**
 * A table's four seats: who sits where, and a button on each free seat
 * while the table waits. The server decides whether sitting is allowed.
 */
export function Seats({ table, userId }: { table: LobbyTable; userId: number }) {
  return (
    <ol className="lobby-seats">
      {table.seats.map((seat) => (
        <li key={seat.seat} className={seat.name === null ? "lobby-seat lobby-seat-free" : "lobby-seat"}>
          <SeatContent table={table} seat={seat} userId={userId} />
        </li>
      ))}
    </ol>
  )
}

function SeatContent({ table, seat, userId }: { table: LobbyTable; seat: LobbySeat; userId: number }) {
  if (seat.name !== null) {
    const notes = [seat.user_id === table.host_id && "vært", seat.user_id === userId && "dig", seat.bot && "bot"].filter(Boolean)
    return (
      <span>
        {seat.name}
        {notes.length > 0 && <span className="lobby-seat-note"> ({notes.join(", ")})</span>}
      </span>
    )
  }
  if (table.status !== "waiting") return <span className="lobby-seat-note">Ledig</span>

  return (
    <PostForm action={tablePaths(table.id).seat}>
      <input type="hidden" name="position" value={seat.seat} />
      <button type="submit">Sæt dig her</button>
    </PostForm>
  )
}
