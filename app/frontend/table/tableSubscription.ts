import { createConsumer, type Consumer } from "@rails/actioncable"
import type { ClientIntents, ServerMessage } from "./messages"

let consumer: Consumer | null = null

interface Handlers {
  onMessage: (message: ServerMessage) => void
  onConnectionChange: (connected: boolean) => void
  onRejected: () => void
}

export interface TableSubscription {
  send<A extends keyof ClientIntents>(action: A, data: ClientIntents[A]): void
  close(): void
}

/** Subscribes to TableChannel for one table. The server sends the full state on subscribe. */
export function subscribeToTable(tableId: number, handlers: Handlers): TableSubscription {
  consumer ??= createConsumer()
  const subscription = consumer.subscriptions.create(
    { channel: "TableChannel", table_id: tableId },
    {
      received: (data: ServerMessage) => handlers.onMessage(data),
      connected: () => handlers.onConnectionChange(true),
      disconnected: () => handlers.onConnectionChange(false),
      rejected: () => handlers.onRejected(),
    },
  )

  return {
    send: (action, data) => {
      subscription.perform(action, data)
    },
    close: () => {
      subscription.unsubscribe()
    },
  }
}
