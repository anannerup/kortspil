import { useEffect, useState } from "react"
import { createConsumer, type Consumer } from "@rails/actioncable"
import { sendTableAction } from "~/lobby/tableActions"
import "./notifications.css"

/** What NotificationsChannel sends (see the channel, Friendship#notify_addressee and WaitingTableBroadcasts). */
export type NotificationMessage =
  | { type: "friend_request"; friendship_id: number; from: string }
  | { type: "presence"; user_id: number; online: boolean }
  /** A puf: `from` nudges you to their bord; answer at `path` (accept or decline). */
  | { type: "nudge"; nudge_id: number; table_id: string; table_name: string; from: string; path: string; expires_at: string }
  /** The puf ended without your answer here (withdrawn, expired, the spil started, the bord closed). */
  | { type: "nudge_gone"; nudge_id: number; table_id: string; state: string }

interface Toast {
  id: number
  text: string
  href?: string
  action?: string
}

type NudgeMessage = Extract<NotificationMessage, { type: "nudge" }>

let consumer: Consumer | null = null
const TOAST_MS = 8000

const nudgeKey = (nudge: { table_id: string; nudge_id: number }) => `${nudge.table_id}:${nudge.nudge_id}`

/**
 * Subscribes to NotificationsChannel on every page, which also keeps the
 * player marked online. Friend requests pop up as toasts; presence changes
 * update the friends list in place (rows marked data-presence-user-id).
 * A puf stays until you answer it, it ends, or its time is up: "Sæt mig
 * ved bordet" seats you and opens the bord; "Nej tak" declines.
 */
export function Notifications({ friendsPath }: { friendsPath: string }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const [nudges, setNudges] = useState<NudgeMessage[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    consumer ??= createConsumer()
    let next = 1
    const subscription = consumer.subscriptions.create(
      { channel: "NotificationsChannel" },
      {
        received: (message: NotificationMessage) => {
          if (message.type === "presence") {
            showPresence(message.user_id, message.online)
            return
          }
          if (message.type === "nudge") {
            setNudges((current) => [...current.filter((nudge) => nudgeKey(nudge) !== nudgeKey(message)), message])
            return
          }
          if (message.type === "nudge_gone") {
            setNudges((current) => current.filter((nudge) => nudgeKey(nudge) !== nudgeKey(message)))
            return
          }
          if (message.type === "friend_request") {
            const toast = { id: next++, text: `${message.from} vil gerne være din ven`, href: friendsPath, action: "Se venner" }
            setToasts((current) => [...current, toast])
            setTimeout(() => setToasts((current) => current.filter((item) => item.id !== toast.id)), TOAST_MS)
          }
        },
      },
    )
    return () => {
      subscription.unsubscribe()
    }
  }, [friendsPath])

  // A puf disappears when its time is up, even if the server has not said so yet.
  useEffect(() => {
    if (nudges.length === 0) return
    const soonest = Math.min(...nudges.map((nudge) => Date.parse(nudge.expires_at)))
    const timer = setTimeout(() => setNudges((current) => current.filter((nudge) => Date.parse(nudge.expires_at) > Date.now())), Math.max(0, soonest - Date.now()))
    return () => clearTimeout(timer)
  }, [nudges])

  const answer = async (nudge: NudgeMessage, accept: boolean) => {
    const result = await sendTableAction(nudge.path, { answer: accept ? "accept" : "decline" }, "patch")
    if ("error" in result && accept) {
      setError(result.error)
      return
    }
    setNudges((current) => current.filter((item) => nudgeKey(item) !== nudgeKey(nudge)))
    if (accept && "table" in result) window.location.assign(result.table.path)
  }

  if (toasts.length === 0 && nudges.length === 0) return null
  return (
    <div className="notify-stack" role="status" aria-live="polite">
      {nudges.map((nudge) => (
        <div key={nudgeKey(nudge)} className="notify-toast notify-nudge">
          <span>
            <strong>{nudge.from}</strong> puffer dig til {nudge.table_name}
            {error && <small className="notify-error">{error}</small>}
          </span>
          <div className="notify-buttons">
            <button type="button" className="notify-action" onClick={() => void answer(nudge, true)}>
              Sæt mig ved bordet
            </button>
            <button type="button" className="notify-decline" onClick={() => void answer(nudge, false)}>
              Nej tak
            </button>
          </div>
        </div>
      ))}
      {toasts.map((toast) => (
        <div key={toast.id} className="notify-toast">
          <span>{toast.text}</span>
          {toast.href && (
            <a className="notify-action" href={toast.href}>
              {toast.action}
            </a>
          )}
          <button type="button" className="notify-close" aria-label="Luk" onClick={() => setToasts((current) => current.filter((item) => item.id !== toast.id))}>
            ×
          </button>
        </div>
      ))}
    </div>
  )
}

/** Updates the presence dot and pill of a friend on the Venner page, if shown. */
function showPresence(userId: number, online: boolean) {
  document.querySelectorAll<HTMLElement>(`[data-presence-user-id="${userId}"]`).forEach((row) => {
    row.querySelector(".presence")?.classList.toggle("online", online)
    const pill = row.querySelector(".presence-pill")
    if (pill) {
      pill.textContent = online ? "Online" : "Offline"
      pill.classList.toggle("pill-green", online)
    }
  })
}
