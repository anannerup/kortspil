// The messages LobbyChannel sends: defined once here. The server builds
// them in LobbyChannel.tables_message from Table#lobby_entry.

import type { Rules, SeatIndex } from "~/table/messages"

export interface LobbySeat {
  seat: SeatIndex
  /** null: the seat is free. */
  name: string | null
  user_id: number | null
  bot: boolean
}

/** One open table as the lobby lists it. */
export interface LobbyTable {
  id: number
  host: string
  host_id: number
  status: "waiting" | "playing"
  rules: Rules
  seats: LobbySeat[]
}

export type LobbyMessage = { type: "tables"; tables: LobbyTable[] }

/** Where a table's pages and forms are (config/routes.rb). */
export function tablePaths(tableId: number) {
  const table = `/tables/${tableId}`
  return { table, seat: `${table}/seat`, start: `${table}/start`, departure: `${table}/departure` }
}
