import { useEffect, useState, type ReactNode } from "react"
import { ChatLog, ChatSheet, UnreadBadge } from "../Chat"
import type { TableChat } from "../useTableChat"
import { useMediaQuery } from "./hooks"
import { leaveConfirmText } from "./routing.ts"

type Tab = "spil" | "stilling" | "regler" | "chat"
const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: "spil", label: "Spil", icon: "🂠" },
  { key: "stilling", label: "Stilling", icon: "☰" },
  { key: "regler", label: "Regler", icon: "⚙" },
  { key: "chat", label: "Chat", icon: "✉" },
]

/** When the panel is a bar under the felt (the media query in table.css). */
const NARROW = "(max-width: 820px), (orientation: portrait)"

/**
 * The white panel beside the felt, its frame the same at every game: the
 * tabs, the "‹ Lobby · …" line (with "Forbinder…" while offline), the
 * status line and the buttons at the bottom (the game's primary button,
 * Chat, Stilling and "Forlad bordet" with its confirmation). On a narrow or
 * portrait screen it is a bar under the felt (CSS) and the chat is a sheet;
 * widened again, the sheet turns back into the chat tab. The game fills
 * the spil, stilling and regler tabs, the info line and the status.
 */
export function TablePanel(props: {
  /** The info line after "‹ Lobby · ": the bord, the runde. */
  info: ReactNode
  connected: boolean
  chat: TableChat
  userId: number
  spil: ReactNode
  stilling: ReactNode
  regler: ReactNode
  /** Extra classes on the tab body (es-makker: "has-choices"). */
  bodyClass?: string
  status: ReactNode
  /** "Næste runde" / "Til bordet" (after the spil), when there is one. */
  primary?: { label: string; onClick: () => void } | null
  onShowScore: () => void
  /** The Stilling button's tooltip. */
  scoreTitle?: string
  /** After the spil leaving needs no confirmation: nothing is lost. */
  finished: boolean
  practice: boolean
  onLeave: () => void
}) {
  const { info, connected, chat, userId, spil, stilling, regler, bodyClass, status, primary, onShowScore, scoreTitle, finished, practice, onLeave } = props
  const [tab, setTab] = useState<Tab>("spil")
  const [chatSheet, setChatSheet] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const narrow = useMediaQuery(NARROW)

  // The sheet is for narrow screens; on a wide one the chat is a tab.
  useEffect(() => {
    if (narrow && tab === "chat") {
      setTab("spil")
      setChatSheet(true)
    } else if (!narrow && chatSheet) {
      setChatSheet(false)
      setTab("chat")
    }
  }, [narrow, chatSheet, tab])
  const { setViewing } = chat
  useEffect(() => setViewing(chatSheet || (!narrow && tab === "chat")), [setViewing, chatSheet, narrow, tab])

  const bodyClasses = ["table-panel-body", tab === "spil" ? "is-spil" : "", tab === "chat" ? "is-chat" : "", bodyClass ?? ""]

  return (
    <aside className="table-panel" aria-label="Spillet">
      <nav className="table-tabs" aria-label="Faner">
        {TABS.map((item) => (
          <button key={item.key} type="button" className={tab === item.key ? "is-on" : undefined} aria-pressed={tab === item.key} onClick={() => setTab(item.key)}>
            <span aria-hidden="true">{item.icon}</span>
            {item.label}
            {item.key === "chat" && tab !== "chat" && <UnreadBadge count={chat.unread} />}
          </button>
        ))}
      </nav>
      <p className="table-panel-info">
        <a href="/" className="table-lobby-link">
          ‹ Lobby
        </a>{" "}
        · {info}
        {!connected && <span className="table-offline"> · Forbinder…</span>}
      </p>

      <div className={bodyClasses.filter(Boolean).join(" ")}>
        {tab === "spil" && spil}
        {tab === "stilling" && stilling}
        {tab === "regler" && regler}
        {tab === "chat" && !narrow && <ChatLog chat={chat} userId={userId} />}
      </div>

      <p className="table-status" aria-live="polite">
        {status}
      </p>
      <div className="table-panel-buttons">
        {primary && (
          <button type="button" className="table-btn table-btn-primary" onClick={primary.onClick}>
            {primary.label}
          </button>
        )}
        <button type="button" className="table-btn table-panel-chat-button" onClick={() => setChatSheet(true)}>
          Chat
          <UnreadBadge count={chat.unread} />
        </button>
        <button type="button" className="table-btn table-panel-score-button" onClick={onShowScore} title={scoreTitle}>
          Stilling
        </button>
        {confirmLeave ? (
          <div className="table-leave-confirm" role="alertdialog" aria-label="Forlad bordet">
            <span>{leaveConfirmText(practice)}</span>
            <button type="button" className="table-btn table-btn-danger" onClick={onLeave}>
              Ja, forlad
            </button>
            <button type="button" className="table-btn" onClick={() => setConfirmLeave(false)}>
              Bliv
            </button>
          </div>
        ) : (
          <button type="button" className="table-btn table-btn-danger" onClick={() => (finished ? onLeave() : setConfirmLeave(true))}>
            Forlad bordet
          </button>
        )}
      </div>
      {chatSheet && <ChatSheet chat={chat} userId={userId} onClose={() => setChatSheet(false)} />}
    </aside>
  )
}
