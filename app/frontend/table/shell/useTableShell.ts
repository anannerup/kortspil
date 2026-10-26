import { useCallback, useEffect, useRef, useState, type MutableRefObject } from "react"
import type { ClientIntents, ServerMessage } from "../messages"
import { subscribeToTable, type TableSubscription } from "../tableSubscription"
import { useTableChat, type TableChat } from "../useTableChat"
import { routeMessage, routeRefusal } from "./routing.ts"

const NOTICE_MS = 3500

/** The part of a game's state the shell reads: its version, and the bord the next spil waits at. */
export interface ShellState {
  version: number
  next_path?: string
}

export type Send = <A extends keyof ClientIntents>(action: A, data: ClientIntents[A]) => void

export interface TableShell {
  connected: boolean
  /** The subscription was refused and there is no next bord: you do not sit here. */
  refused: boolean
  /** Why your last move was refused, for a while (until it fades or a newer state comes). */
  notice: string | null
  /** The tur-ur's warning on your turn, until a newer state comes. */
  warning: string | null
  chat: TableChat
  send: Send
  /** The hidden form that stands you up from the bord (LeaveForm), and submitting it. */
  leaveForm: MutableRefObject<HTMLFormElement | null>
  leave: () => void
}

/**
 * A bord's subscription, the same at every game: it routes TableChannel's
 * messages (routeMessage), keeps the notice, the tur-ur's warning and the
 * connection, and remembers `next_path` so a refused reconnect after the
 * spil goes on to the new bord. Each state goes to `onState`, the game's
 * page (its timeline); `onRejected` lets the page undo what it showed as
 * sent. Both may change between renders without resubscribing.
 */
export function useTableShell<S extends ShellState>(options: {
  tableId: number
  userId: number
  onState: (state: S) => void
  onRejected?: () => void
}): TableShell {
  const { tableId, userId } = options
  const [connected, setConnected] = useState(false)
  const [refused, setRefused] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [warning, setWarning] = useState<string | null>(null)
  const subscription = useRef<TableSubscription | null>(null)
  const nextPath = useRef<string | null>(null)
  const version = useRef<number | null>(null)
  const leaveForm = useRef<HTMLFormElement | null>(null)
  const leave = useCallback(() => leaveForm.current?.requestSubmit(), [])
  const page = useRef(options)
  page.current = options

  const send: Send = useCallback((action, data) => subscription.current?.send(action, data), [])
  const chat = useTableChat(userId, useCallback((text: string) => send("chat", { text }), [send]))
  const receiveChat = chat.receive

  useEffect(() => {
    const handle = (message: ServerMessage<S>) => {
      const route = routeMessage(message)
      switch (route.kind) {
        case "chat":
          receiveChat(message)
          return
        case "go":
          window.location.assign(route.to)
          return
        case "reload":
          window.location.reload()
          return
        case "warning":
          setWarning(route.text)
          return
        case "rejected":
          setNotice(route.notice)
          page.current.onRejected?.()
          return
        case "state":
          setNotice(null)
          // The warning lasts until something happens in the spil.
          if (version.current !== null && route.state.version > version.current) setWarning(null)
          version.current = Math.max(version.current ?? 0, route.state.version)
          if (route.state.next_path) nextPath.current = route.state.next_path
          page.current.onState(route.state)
      }
    }
    subscription.current = subscribeToTable<S>(tableId, {
      onMessage: handle,
      onConnectionChange: setConnected,
      onRejected: () => {
        const refusal = routeRefusal(nextPath.current)
        if (refusal.kind === "go") window.location.assign(refusal.to)
        else setRefused(true)
      },
    })
    return () => subscription.current?.close()
  }, [tableId, receiveChat])

  // Notices fade after a while.
  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(null), NOTICE_MS)
    return () => clearTimeout(timer)
  }, [notice])

  return { connected, refused, notice, warning, chat, send, leaveForm, leave }
}
