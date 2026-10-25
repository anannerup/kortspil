import { createConsumer, type Consumer } from "@rails/actioncable"
import type { ClientIntents, ServerMessage } from "./messages"

let consumer: Consumer | null = null

/** How often the client says it is still here; the server allows about 10 s of silence (TurnClock). */
const HEARTBEAT_MS = 4000

interface Handlers {
  onMessage: (message: ServerMessage) => void
  onConnectionChange: (connected: boolean) => void
  onRejected: () => void
}

export interface TableSubscription {
  send<A extends keyof ClientIntents>(action: A, data: ClientIntents[A]): void
  close(): void
}

/**
 * Subscribes to TableChannel for one table. The server sends the full state
 * on subscribe. While connected, a heartbeat goes every few seconds, so the
 * server notices a closed tab or a dropped network within seconds (a
 * subscription that closes counts as frakoblet at once). A bord before its
 * spil (a string id: it lives in memory) has only the chat, and no
 * heartbeat.
 */
export function subscribeToTable(tableId: number | string, handlers: Handlers): TableSubscription {
  const waiting = typeof tableId === "string"
  consumer ??= createConsumer()
  let heartbeat: ReturnType<typeof setInterval> | null = null
  const stopHeartbeat = () => {
    if (heartbeat !== null) clearInterval(heartbeat)
    heartbeat = null
  }
  const subscription = consumer.subscriptions.create(
    waiting ? { channel: "TableChannel", waiting_table_id: tableId } : { channel: "TableChannel", table_id: tableId },
    {
      received: (data: ServerMessage) => handlers.onMessage(data),
      connected: () => {
        stopHeartbeat()
        if (!waiting) heartbeat = setInterval(() => subscription.perform("heartbeat", {}), HEARTBEAT_MS)
        handlers.onConnectionChange(true)
      },
      disconnected: () => {
        stopHeartbeat()
        handlers.onConnectionChange(false)
      },
      rejected: () => handlers.onRejected(),
    },
  )

  return {
    send: (action, data) => {
      subscription.perform(action, data)
    },
    close: () => {
      stopHeartbeat()
      subscription.unsubscribe()
    },
  }
}
