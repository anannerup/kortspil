import { useEffect, useState } from "react"
import type { LobbyTable } from "./messages"
import { subscribeToLobby } from "./lobbySubscription"

/**
 * The listed borde: the list the page was rendered with, then each list
 * LobbyChannel sends. `live` turns true with the first list from the channel.
 */
export function useLobbyTables(initial: LobbyTable[]): { tables: LobbyTable[]; live: boolean } {
  const [tables, setTables] = useState(initial)
  const [live, setLive] = useState(false)

  useEffect(() => {
    const subscription = subscribeToLobby((message) => {
      if (message.type !== "tables") return
      setTables(message.tables)
      setLive(true)
    })
    return () => subscription.close()
  }, [])

  return { tables, live }
}

/** Milliseconds until the next pending puf expires, or null. */
export function nextExpiry(table: LobbyTable, now: number): number | null {
  const times = table.nudges.filter((nudge) => nudge.state === "pending").map((nudge) => Date.parse(nudge.expires_at) - now)
  return times.length === 0 ? null : Math.max(0, Math.min(...times))
}

/**
 * One bord for its page before the spil: the entry the page was rendered
 * with, then each one LobbyChannel sends for it, or the page's own actions
 * answer with (`setTable`). `live` turns true with the first from the
 * channel. When a pending puf's time is up the page asks the server to let
 * it expire, so everyone sees it. A practice bord has no channel: only its
 * player changes it.
 */
export function useWaitingTable(initial: LobbyTable): { table: LobbyTable; setTable: (table: LobbyTable) => void; live: boolean } {
  const [table, setTable] = useState(initial)
  const [live, setLive] = useState(false)
  const [subscription, setSubscription] = useState<ReturnType<typeof subscribeToLobby> | null>(null)
  const practice = initial.kind === "practice"

  useEffect(() => {
    if (practice) return
    const created = subscribeToLobby((message) => {
      if (message.type !== "table") return
      setTable(message.table)
      setLive(true)
    }, String(initial.id))
    setSubscription(created)
    return () => {
      created.close()
      setSubscription(null)
    }
  }, [initial.id, practice])

  useEffect(() => {
    const wait = nextExpiry(table, Date.now())
    if (wait === null || !subscription) return
    // A little after the expiry, so the server's clock has passed it too.
    const timer = setTimeout(() => subscription.expireNudges(), wait + 500)
    return () => clearTimeout(timer)
  }, [table, subscription])

  return { table, setTable, live }
}
