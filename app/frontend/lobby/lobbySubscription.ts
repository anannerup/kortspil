import { createConsumer } from "@rails/actioncable"
import type { LobbyMessage } from "./messages"

/** Subscribes to LobbyChannel. The server sends the whole list on subscribe and after each change. */
export function subscribeToLobby(onMessage: (message: LobbyMessage) => void): () => void {
  const consumer = createConsumer()
  const subscription = consumer.subscriptions.create({ channel: "LobbyChannel" }, { received: onMessage })
  return () => {
    subscription.unsubscribe()
    consumer.disconnect()
  }
}
