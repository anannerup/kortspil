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

/** One table as the lobby lists it, or as its table page shows it before the spil. */
export interface LobbyTable {
  id: number
  /** "practice" reaches only the practice bord's own page: the lobby never lists it. */
  kind: TableKind | "practice"
  host: string
  host_id: number
  /** "closed" reaches only the table's own page: the lobby list drops closed tables. */
  status: "waiting" | "playing" | "closed"
  rules: Rules
  seats: LobbySeat[]
}

export type LobbyMessage =
  /** The lobby's list of open and password tables. */
  | { type: "tables"; tables: LobbyTable[] }
  /** One table, to its own page before the spil. */
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
