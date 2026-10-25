import { createConsumer } from "@rails/actioncable"
import type { LobbyMessage } from "./messages"

export interface LobbySubscription {
  /** Asks the bord to let pufs whose time is up expire (LobbyChannel#expire_nudges). */
  expireNudges(): void
  close(): void
}

/**
 * Subscribes to LobbyChannel. The server sends the whole list on subscribe
 * and after each change; with `waitingTableId`, that one bord before its
 * spil instead (private borde included).
 */
export function subscribeToLobby(onMessage: (message: LobbyMessage) => void, waitingTableId?: string): LobbySubscription {
  const consumer = createConsumer()
  const params = waitingTableId === undefined ? { channel: "LobbyChannel" } : { channel: "LobbyChannel", waiting_table_id: waitingTableId }
  const subscription = consumer.subscriptions.create(params, { received: onMessage })
  return {
    expireNudges: () => {
      subscription.perform("expire_nudges", {})
    },
    close: () => {
      subscription.unsubscribe()
      consumer.disconnect()
    },
  }
}
