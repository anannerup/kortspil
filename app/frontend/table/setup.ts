import type { Friend, LobbyNudge, LobbySeat, LobbyTable } from "~/lobby/messages"
import type { SeatIndex } from "./messages"
import type { Position } from "./Trick"

/**
 * The bord before its spil, as its table page shows it: who looks at it
 * from where, what each seat is, and what is missing before the vært can
 * start, and the vært's pufs. Pure: labels from the entry the server sends
 * (WaitingTable#lobby_entry); the server decides what is allowed.
 */

export const SEAT_COUNT = 4

/** Clockwise from where you sit, as during play (Trick.tsx). */
const AROUND: Position[] = ["south", "west", "north", "east"]

/** The seat the user sits in, or null. */
export function seatOf(table: LobbyTable, userId: number): SeatIndex | null {
  return table.seats.find((seat) => seat.user_id === userId)?.seat ?? null
}

/** Where `seat` is drawn for someone in seat `me`: you are always south. A visitor looks from seat 0. */
export function positionOf(seat: SeatIndex, me: SeatIndex | null): Position {
  return AROUND[(seat - (me ?? 0) + SEAT_COUNT) % SEAT_COUNT] ?? "south"
}

/** The seat drawn at `position` for someone in seat `me`. */
export function seatAt(table: LobbyTable, position: Position, me: SeatIndex | null): LobbySeat | undefined {
  return table.seats.find((seat) => positionOf(seat.seat, me) === position)
}

export const isEmpty = (seat: LobbySeat) => seat.name === null

export const emptySeats = (table: LobbyTable) => table.seats.filter(isEmpty).length

/** Every seat holds a human or a bot (only humans where bots may not sit): the vært may start. */
export const canStart = (table: LobbyTable) =>
  table.status === "waiting" && emptySeats(table) === 0 && (table.bots_allowed || table.seats.every((seat) => !seat.bot))

/** How long a spil at the bord lasts: "Til 100 point" (hjerterfri), "10 runder" (es-makker). */
export const lengthLabel = (table: LobbyTable) => (table.game === "esmakker" ? `${table.runder ?? "?"} runder` : `Til ${table.rules.end_score} point`)

/** What a seat's occupant is to you: "vært", "dig", "bot". */
export function seatRoles(seat: LobbySeat, table: LobbyTable, userId: number): string[] {
  if (isEmpty(seat)) return []
  return [seat.user_id === table.host_id && "vært", seat.user_id === userId && "dig", seat.bot && "bot"].filter((role): role is string => Boolean(role))
}

const players = (count: number) => (count === 1 ? "1 spiller" : `${count} spillere`)

/** The short line in the middle of the table. */
export function centreLine(table: LobbyTable): string {
  const missing = emptySeats(table)
  if (missing === 0) return "Alle pladser er besat"
  return `Venter på ${players(missing)}`
}

/** What happens next, for the user: the status line in the panel. */
export function setupStatus(table: LobbyTable, userId: number): string {
  const missing = emptySeats(table)
  const isHost = table.host_id === userId
  if (table.kind === "practice") return "Dig mod tre bots. Vælg reglerne, og start spillet, når du er klar."
  if (seatOf(table, userId) === null) return missing > 0 ? "Vælg en ledig plads for at sætte dig ved bordet." : "Bordet er fuldt."
  if (missing === 0) return isHost ? "Alle pladser er besat. Start spillet, når I er klar." : `Alle pladser er besat. ${table.host} starter spillet.`
  if (isHost) return table.bots_allowed ? `Der mangler ${players(missing)}. Inviter nogen, eller sæt bots på de ledige pladser.` : `Der mangler ${players(missing)}. Inviter nogen; ${GAME_NAMES[table.game].toLowerCase()} spilles af fire spillere.`
  return `Der mangler ${players(missing)}. ${table.host} starter spillet, når alle pladser er besat.`
}

/** The game's name, as the lobby's boxes show it. */
export const GAME_NAMES: Record<LobbyTable["game"], string> = { hjerterfri: "Hjerterfri", esmakker: "Es-makker" }

/** The latest puf to the friend, from anyone at the bord, if any. */
export function nudgeFor(table: LobbyTable, friendId: number): LobbyNudge | undefined {
  return table.nudges.find((nudge) => nudge.user_id === friendId)
}

/** Free seats not held by a pending puf: room for another puf (pending + seated + bots ≤ 4). */
export const freeForNudge = (table: LobbyTable) => emptySeats(table) - table.reserved

/**
 * What your puf list says about a friend, whether you can nudge them (again)
 * now, and the pending puf to them (`pending`), which you can withdraw
 * (`canWithdraw`) if you sent it or are the vært.
 */
export function friendStatus(
  table: LobbyTable,
  friend: Friend,
  userId: number,
): { label: string; canNudge: boolean; pending: LobbyNudge | null; canWithdraw: boolean } {
  return { canWithdraw: false, ...friendState(table, friend, userId) }
}

function friendState(table: LobbyTable, friend: Friend, userId: number) {
  if (table.seats.some((seat) => seat.user_id === friend.id)) return { label: "Sidder ved bordet", canNudge: false, pending: null }
  const nudge = nudgeFor(table, friend.id)
  const room = freeForNudge(table) > 0
  const online = friend.online ? "Online" : "Offline"
  switch (nudge?.state) {
    case "pending": {
      const by = nudge.from_id === userId ? "" : ` af ${nudge.from_name}`
      return { label: `Puffet${by} · venter på svar`, canNudge: false, pending: nudge, canWithdraw: nudge.from_id === userId || table.host_id === userId }
    }
    case "declined":
      return { label: "Sagde nej tak", canNudge: room, pending: null }
    case "expired":
      return { label: "Puffet udløb", canNudge: room, pending: null }
    case "accepted":
      return { label: "Sagde ja", canNudge: room, pending: null }
    default:
      return { label: online, canNudge: room, pending: null }
  }
}
