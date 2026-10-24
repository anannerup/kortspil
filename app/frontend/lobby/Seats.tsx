import type { LobbySeat, LobbyTable } from "./messages"
import { tablePaths } from "./messages"
import { PostForm } from "./PostForm"

export const SEAT_COUNT = 4

export const takenSeats = (table: LobbyTable) => table.seats.filter((seat) => seat.name !== null).length

export function statusLabel(table: LobbyTable): string {
  if (table.status === "playing") return "I gang"
  if (table.status === "closed") return "Lukket"
  return `Venter på spillere (${takenSeats(table)}/${SEAT_COUNT})`
}

/**
 * A table's four seats: who sits where, and a "Sæt dig her" button on each
 * free seat while the table waits. Every seat's button submits one sit
 * form, which holds the password field at a password table the user does
 * not sit at yet. With `hostControls` (the vært, in the waiting room) each
 * seat also gets the vært's buttons: kick a player, add or remove a bot.
 * The server decides whether any of it is allowed.
 */
export function Seats({ table, userId, hostControls = false }: { table: LobbyTable; userId: number; hostControls?: boolean }) {
  const seated = table.seats.some((seat) => seat.user_id === userId)
  const canSit = table.status === "waiting" && takenSeats(table) < SEAT_COUNT
  const needsPassword = canSit && table.kind === "password" && !seated
  const sitForm = `sit-${table.id}`

  return (
    <>
      {canSit && (
        <PostForm action={tablePaths(table.id).seat} id={sitForm} className="lobby-sit">
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
            <SeatContent table={table} seat={seat} userId={userId} sitForm={sitForm} hostControls={hostControls} />
          </li>
        ))}
      </ol>
    </>
  )
}

function SeatContent(props: { table: LobbyTable; seat: LobbySeat; userId: number; sitForm: string; hostControls: boolean }) {
  const { table, seat, userId, sitForm, hostControls } = props
  const paths = tablePaths(table.id)
  const waiting = table.status === "waiting"

  if (seat.name !== null) {
    const notes = [seat.user_id === table.host_id && "vært", seat.user_id === userId && "dig", seat.bot && "bot"].filter(Boolean)
    const kickable = hostControls && waiting && !seat.bot && seat.user_id !== userId
    return (
      <>
        <span className="lobby-seat-name">
          {seat.name}
          {notes.length > 0 && <span className="lobby-seat-note"> ({notes.join(", ")})</span>}
        </span>
        {kickable && (
          <PostForm action={paths.kick} confirm={`Fjern ${seat.name} fra bordet?`}>
            <input type="hidden" name="position" value={seat.seat} />
            <button type="submit" className="btn btn-quiet-danger">
              Fjern
            </button>
          </PostForm>
        )}
        {hostControls && waiting && seat.bot && (
          <PostForm action={paths.bot} method="delete">
            <input type="hidden" name="position" value={seat.seat} />
            <button type="submit" className="btn btn-quiet">
              Fjern bot
            </button>
          </PostForm>
        )}
      </>
    )
  }
  if (!waiting) return <span className="lobby-seat-note">Ledig</span>

  return (
    <>
      <button type="submit" form={sitForm} name="position" value={seat.seat} className="btn btn-primary">
        Sæt dig her
      </button>
      {hostControls && (
        <PostForm action={paths.bot}>
          <input type="hidden" name="position" value={seat.seat} />
          <button type="submit" className="btn btn-secondary">
            Sæt en bot her
          </button>
        </PostForm>
      )}
    </>
  )
}
