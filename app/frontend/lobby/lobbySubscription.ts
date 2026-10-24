import { createConsumer } from "@rails/actioncable"
import type { LobbyMessage } from "./messages"

/**
 * Subscribes to LobbyChannel. The server sends the whole list on subscribe
 * and after each change; with `tableId`, that one table instead (a waiting
 * room, private tables included).
 */
export function subscribeToLobby(onMessage: (message: LobbyMessage) => void, tableId?: number): () => void {
  const consumer = createConsumer()
  const params = tableId === undefined ? { channel: "LobbyChannel" } : { channel: "LobbyChannel", table_id: tableId }
  const subscription = consumer.subscriptions.create(params, { received: onMessage })
  return () => {
    subscription.unsubscribe()
    consumer.disconnect()
  }
}
