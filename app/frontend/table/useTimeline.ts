import { useCallback, useEffect, useRef, useState } from "react"
import { useReducedMotion } from "motion/react"
import type { TableState } from "./messages"
import { framesFor, type Frame } from "./timeline"

/** A frame on screen, and when its state arrived (performance.now()), for the clocks. */
export interface Shown {
  frame: Frame
  at: number
}

/**
 * Plays the server's states back as frames (timeline.ts): each frame stays
 * on screen for its hold before the next one shows. `push` takes every
 * state as it arrives; a state older than the newest one is ignored
 * (messages can cross on the wire).
 */
export function useTimeline() {
  const reduced = useReducedMotion() ?? false
  const reducedNow = useRef(reduced)
  reducedNow.current = reduced
  const [shown, setShown] = useState<Shown | null>(null)
  const queue = useRef<Shown[]>([])
  const newest = useRef<Frame | null>(null)
  const holding = useRef<ReturnType<typeof setTimeout> | null>(null)

  const pump = useCallback(() => {
    while (!holding.current) {
      const next = queue.current.shift()
      if (!next) return
      setShown(next)
      if (next.frame.hold > 0) {
        holding.current = setTimeout(() => {
          holding.current = null
          pump()
        }, next.frame.hold)
      }
    }
  }, [])

  const push = useCallback(
    (state: TableState) => {
      const last = newest.current
      if (last && last.state.game_id === state.game_id && last.state.version > state.version) return
      const at = performance.now()
      const frames = framesFor(last, state, reducedNow.current)
      for (const frame of frames) queue.current.push({ frame, at })
      newest.current = frames.at(-1) ?? last
      pump()
    },
    [pump],
  )

  useEffect(
    () => () => {
      if (holding.current) clearTimeout(holding.current)
      holding.current = null
    },
    [],
  )

  return [shown, push] as const
}
