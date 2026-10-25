// The messages LobbyChannel sends: defined once here. The server builds
// them in LobbyChannel from WaitingTable#lobby_entry (a bord before its
// spil, in memory) and Table#lobby_entry (a stored bord, playing).

import type { Rules, SeatIndex } from "~/table/messages"

export interface LobbySeat {
  seat: SeatIndex
  /** null: the seat is free. */
  name: string | null
  user_id: number | null
  bot: boolean
}

/** TableRules::CHOOSABLE_KINDS: the lobby lists open and password tables; private ones only have their link. */
export type TableKind = "open" | "password" | "private"

/** The games a bord can be made for (WaitingTable::GAMES); only hjerterfri is built. */
export type GameKind = "hjerterfri"

export type NudgeState = "pending" | "accepted" | "declined" | "withdrawn" | "expired"

/** A puf from the vært to a friend (WaitingTable::Nudge). */
export interface LobbyNudge {
  id: number
  user_id: number
  name: string
  state: NudgeState
  /** ISO time: when a pending puf expires. */
  expires_at: string
}

/** One bord as the lobby lists it, or as its page shows it before the spil. */
export interface LobbyTable {
  /** A waiting bord's id is a string (it lives in memory); a stored table's a number. */
  id: string | number
  /** "Annas bord", "Bord 12", "Øvebord". */
  name: string
  /** The bord's page: /borde/:id before the spil, /tables/:id once it is stored. */
  path: string
  game: GameKind
  /** "practice" reaches only the practice bord's own page: the lobby never lists it. */
  kind: TableKind | "practice"
  host: string
  host_id: number
  /** "closed" reaches only the bord's own page: the lobby list drops closed borde. "playing": it has been stored and its spil runs. */
  status: "waiting" | "playing" | "closed"
  rules: Rules
  seats: LobbySeat[]
  /** The vært's pufs and their states (before the spil only). */
  nudges: LobbyNudge[]
  /** Free seats held by pending pufs. */
  reserved: number
}

/** A friend of the user, for the vært's puf list (WaitingTablesController#show). */
export interface Friend {
  id: number
  username: string
  online: boolean
}

export type LobbyMessage =
  /** The lobby's list of open and password tables. */
  | { type: "tables"; tables: LobbyTable[] }
  /** One bord, to its own page before the spil; once it started, the stored table's entry. */
  | { type: "table"; table: LobbyTable }

/** Where a bord's forms are before its spil (config/routes.rb), from its page path. */
export function tablePaths(path: string) {
  const table = path
  return {
    table,
    seat: `${table}/seat`,
    start: `${table}/start`,
    departure: `${table}/departure`,
    kick: `${table}/kick`,
    bot: `${table}/bot`,
    settings: `${table}/settings`,
    nudges: `${table}/nudges`,
  }
}
