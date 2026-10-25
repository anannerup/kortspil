import { useEffect, useRef, useState } from "react"
import { chatTime, useTableChat, type TableChat } from "./useTableChat"
import "./chat.css"

/**
 * The table chat: the messages (author and time, plain text) with the
 * newest at the bottom, and a big input with a send button. Text is
 * rendered as text, never as HTML.
 */
export function ChatLog({ chat, userId }: { chat: TableChat; userId: number }) {
  const list = useRef<HTMLOListElement | null>(null)
  const newestId = chat.messages.at(-1)?.id

  useEffect(() => {
    const element = list.current
    if (element) element.scrollTop = element.scrollHeight
  }, [newestId])

  return (
    <div className="chat">
      <ol ref={list} className="chat-list" aria-live="polite" aria-label="Beskeder">
        {chat.messages.length === 0 && <li className="chat-empty">Ingen beskeder endnu. Sig hej!</li>}
        {chat.messages.map((entry) => (
          <li key={entry.id} className={`chat-entry${entry.user_id === userId ? " is-mine" : ""}`}>
            <span className="chat-meta">
              <strong>{entry.user_id === userId ? "Dig" : entry.name}</strong> <time dateTime={entry.at}>{chatTime(entry.at)}</time>
            </span>
            <span className="chat-text">{entry.text}</span>
          </li>
        ))}
      </ol>
      {chat.notice && (
        <p className="chat-notice" role="alert">
          {chat.notice}
        </p>
      )}
      <ChatForm maxLength={chat.maxLength} refused={chat.refused} onPost={chat.post} />
    </div>
  )
}

/** The input and Send. The draft is its own state: typing renders only this. */
function ChatForm(props: { maxLength: number; refused: TableChat["refused"]; onPost: (text: string) => void }) {
  const { maxLength, refused, onPost } = props
  const [draft, setDraft] = useState("")
  // A refused message comes back into an empty input.
  useEffect(() => {
    if (refused) setDraft((current) => current || refused.text)
  }, [refused])
  return (
    <form
      className="chat-form"
      onSubmit={(event) => {
        event.preventDefault()
        const text = draft.trim()
        if (!text) return
        setDraft("")
        onPost(text)
      }}
    >
      <input
        className="chat-input"
        type="text"
        enterKeyHint="send"
        autoComplete="off"
        aria-label="Skriv en besked"
        placeholder="Skriv en besked…"
        maxLength={maxLength}
        value={draft}
        onChange={(event) => setDraft(event.target.value)}
      />
      <button type="submit" className="table-btn table-btn-primary chat-send" disabled={draft.trim() === ""}>
        Send
      </button>
    </form>
  )
}

/** The unread count on the Chat tab and button. */
export function UnreadBadge({ count }: { count: number }) {
  if (count === 0) return null
  return (
    <span className="chat-badge" aria-label={count === 1 ? "1 ny besked" : `${count} nye beskeder`}>
      {count > 9 ? "9+" : count}
    </span>
  )
}

/** The chat as a sheet over the table, on narrow or portrait screens. */
export function ChatSheet({ chat, userId, onClose }: { chat: TableChat; userId: number; onClose: () => void }) {
  useEffect(() => {
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose()
    }
    window.addEventListener("keydown", close)
    return () => window.removeEventListener("keydown", close)
  }, [onClose])

  return (
    <div
      className="chat-sheet-backdrop"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div className="chat-sheet" role="dialog" aria-modal="true" aria-label="Chat">
        <div className="chat-sheet-header">
          <h2>Chat</h2>
          <button type="button" className="table-btn" onClick={onClose}>
            Luk
          </button>
        </div>
        <ChatLog chat={chat} userId={userId} />
      </div>
    </div>
  )
}
