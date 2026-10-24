import { useEffect, useState } from "react"
import { createConsumer, type Consumer } from "@rails/actioncable"
import "./notifications.css"

/** What NotificationsChannel sends (see the channel and Friendship#notify_addressee). */
export type NotificationMessage =
  | { type: "friend_request"; friendship_id: number; from: string }
  | { type: "presence"; user_id: number; online: boolean }

interface Toast {
  id: number
  text: string
  href?: string
  action?: string
}

let consumer: Consumer | null = null
const TOAST_MS = 8000

/**
 * Subscribes to NotificationsChannel on every page, which also keeps the
 * player marked online. Friend requests pop up as toasts; presence changes
 * update the friends list in place (rows marked data-presence-user-id).
 */
export function Notifications({ friendsPath }: { friendsPath: string }) {
  const [toasts, setToasts] = useState<Toast[]>([])

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

  if (toasts.length === 0) return null
  return (
    <div className="notify-stack" role="status" aria-live="polite">
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
