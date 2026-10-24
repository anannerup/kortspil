// The messages LobbyChannel sends: defined once here. The server builds
// them in LobbyChannel.tables_message and .table_message from
// Table#lobby_entry.

import type { Rules, SeatIndex } from "~/table/messages"

export interface LobbySeat {
  seat: SeatIndex
  /** null: the seat is free. */
  name: string | null
  user_id: number | null
  bot: boolean
}

/** Table::CHOOSABLE_KINDS: the lobby lists open and password tables; private ones only have their link. */
export type TableKind = "open" | "password" | "private"

/** One table as the lobby lists it, or as its waiting room shows it. */
export interface LobbyTable {
  id: number
  kind: TableKind
  host: string
  host_id: number
  /** "closed" reaches only a waiting room: the lobby list drops closed tables. */
  status: "waiting" | "playing" | "closed"
  rules: Rules
  seats: LobbySeat[]
}

export type LobbyMessage =
  /** The lobby's list of open and password tables. */
  | { type: "tables"; tables: LobbyTable[] }
  /** One table, to its waiting room. */
  | { type: "table"; table: LobbyTable }

/** Where a table's pages and forms are (config/routes.rb). */
export function tablePaths(tableId: number) {
  const table = `/tables/${tableId}`
  return {
    table,
    seat: `${table}/seat`,
    start: `${table}/start`,
    departure: `${table}/departure`,
    kick: `${table}/kick`,
    bot: `${table}/bot`,
    settings: `${table}/settings`,
  }
}
