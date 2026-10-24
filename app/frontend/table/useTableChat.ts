import { useCallback, useEffect, useRef, useState } from "react"
import type { ChatEntry, ChatRejection, SeatIndex, ServerMessage } from "./messages"

/** How long a new message shows as a speech bubble at the author's name tag. */
const BUBBLE_MS = 5000
const NOTICE_MS = 4000

export interface TableChat {
  messages: ChatEntry[]
  maxLength: number
  /** Messages from others that came while the chat was not on screen. */
  unread: number
  /** Why your last message was refused, for a while. */
  notice: string | null
  /** The newest message per seat, while its speech bubble shows. */
  bubbles: ReadonlyMap<SeatIndex, ChatEntry>
  draft: string
  setDraft: (text: string) => void
  /** Sends the draft. */
  post: () => void
  /** Whether the chat is on screen now; while it is, everything counts as read. */
  setViewing: (viewing: boolean) => void
  /** Takes a chat message off the table stream; false for any other message. */
  receive: (message: ServerMessage) => boolean
}

/**
 * The table chat as the server sends it (chat_history, chat_message,
 * chat_rejected): the messages, what is unread, the draft and the speech
 * bubbles. `send` posts through the table subscription.
 */
export function useTableChat(userId: number, send: (text: string) => void): TableChat {
  const [messages, setMessages] = useState<ChatEntry[]>([])
  const [maxLength, setMaxLength] = useState(300)
  const [seenId, setSeenId] = useState<number | null>(null)
  const [viewing, setViewing] = useState(false)
  const [rejection, setRejection] = useState<ChatRejection | null>(null)
  const [bubbles, setBubbles] = useState<ReadonlyMap<SeatIndex, ChatEntry>>(new Map())
  const [draft, setDraft] = useState("")
  const lastSent = useRef("")
  const timers = useRef(new Map<SeatIndex, ReturnType<typeof setTimeout>>())

  const newestId = messages.at(-1)?.id ?? 0
  // The first history counts as read; so does everything while on screen.
  useEffect(() => {
    if (viewing) setSeenId(newestId)
  }, [viewing, newestId])

  useEffect(() => {
    if (!rejection) return
    const timer = setTimeout(() => setRejection(null), NOTICE_MS)
    return () => clearTimeout(timer)
  }, [rejection])

  useEffect(() => {
    const pending = timers.current
    return () => pending.forEach((timer) => clearTimeout(timer))
  }, [])

  const showBubble = useCallback((entry: ChatEntry) => {
    setBubbles((current) => new Map(current).set(entry.seat, entry))
    clearTimeout(timers.current.get(entry.seat))
    timers.current.set(
      entry.seat,
      setTimeout(() => {
        setBubbles((current) => {
          if (current.get(entry.seat)?.id !== entry.id) return current
          const next = new Map(current)
          next.delete(entry.seat)
          return next
        })
      }, BUBBLE_MS),
    )
  }, [])

  const receive = useCallback(
    (message: ServerMessage) => {
      switch (message.type) {
        case "chat_history":
          setMessages(message.messages)
          setMaxLength(message.max_length)
          setSeenId((seen) => seen ?? message.messages.at(-1)?.id ?? 0)
          return true
        case "chat_message":
          setMessages((current) => (current.some((entry) => entry.id === message.message.id) ? current : [...current, message.message].slice(-50)))
          showBubble(message.message)
          return true
        case "chat_rejected":
          setRejection(message.reason)
          setDraft((current) => current || lastSent.current)
          return true
        default:
          return false
      }
    },
    [showBubble],
  )

  const post = () => {
    const text = draft.trim()
    if (!text) return
    lastSent.current = text
    setDraft("")
    send(text)
  }

  const unread = messages.filter((entry) => entry.id > (seenId ?? Infinity) && entry.user_id !== userId).length

  const notice = rejection && chatRejectionText(rejection, maxLength)

  return { messages, maxLength, unread, notice, bubbles, draft, setDraft, post, setViewing, receive }
}

function chatRejectionText(reason: ChatRejection, maxLength: number): string {
  switch (reason) {
    case "blank":
      return "Skriv en besked først."
    case "too_long":
      return `Beskeden er for lang. Højst ${maxLength} tegn.`
    case "too_fast":
      return "Du skriver for hurtigt. Vent et øjeblik."
  }
}

/** "19:30": the time a message was written, in local time. */
export function chatTime(at: string): string {
  return new Date(at).toLocaleTimeString("da-DK", { hour: "2-digit", minute: "2-digit" })
}
