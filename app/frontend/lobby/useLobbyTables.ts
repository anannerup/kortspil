import { useEffect, useState } from "react"
import type { LobbyTable } from "./messages"
import { subscribeToLobby } from "./lobbySubscription"

/**
 * The open tables: the list the page was rendered with, then each list
 * LobbyChannel sends. `live` turns true with the first list from the channel.
 */
export function useLobbyTables(initial: LobbyTable[]): { tables: LobbyTable[]; live: boolean } {
  const [tables, setTables] = useState(initial)
  const [live, setLive] = useState(false)

  useEffect(
    () =>
      subscribeToLobby((message) => {
        if (message.type !== "tables") return
        setTables(message.tables)
        setLive(true)
      }),
    [],
  )

  return { tables, live }
}

/**
 * One table for its waiting room: the entry the page was rendered with,
 * then each one LobbyChannel sends for it. `live` turns true with the first.
 */
export function useWaitingTable(initial: LobbyTable): { table: LobbyTable; live: boolean } {
  const [table, setTable] = useState(initial)
  const [live, setLive] = useState(false)

  useEffect(
    () =>
      subscribeToLobby((message) => {
        if (message.type !== "table") return
        setTable(message.table)
        setLive(true)
      }, initial.id),
    [initial.id],
  )

  return { table, live }
}
