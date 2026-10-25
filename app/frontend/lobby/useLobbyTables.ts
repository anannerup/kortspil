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
 * One table for its page before the spil: the entry the page was rendered
 * with, then each one LobbyChannel sends for it, or the page's own actions
 * answer with (`setTable`). `live` turns true with the first from the
 * channel. A practice table has no channel: only its player changes it.
 */
export function useWaitingTable(initial: LobbyTable): { table: LobbyTable; setTable: (table: LobbyTable) => void; live: boolean } {
  const [table, setTable] = useState(initial)
  const [live, setLive] = useState(false)
  const practice = initial.kind === "practice"

  useEffect(() => {
    if (practice) return
    return subscribeToLobby((message) => {
      if (message.type !== "table") return
      setTable(message.table)
      setLive(true)
    }, initial.id)
  }, [initial.id, practice])

  return { table, setTable, live }
}
