import { useCallback, useEffect, useRef, useState } from "react"
import { useReducedMotion } from "motion/react"
import type { Frame } from "./timeline"

/** What a timeline frame needs: the state it shows and how long it stays. */
interface TimedFrame<S> {
  state: S
  hold: number
}

/** The states a timeline plays back: a spil's, with a version. */
interface VersionedState {
  game_id: number
  version: number
}

/** A frame on screen, and when its state arrived (performance.now()), for the clocks. */
export interface Shown<F = Frame> {
  frame: F
  at: number
}

/**
 * Plays the server's states back as frames (timeline.ts): each frame stays
 * on screen for its hold before the next one shows. `push` takes every
 * state as it arrives; a state older than the newest one is ignored
 * (messages can cross on the wire). The game's frames come from
 * `framesFor` (hjerterfri's timeline.ts, es-makker's esmakker/timeline.ts);
 * pass a stable function.
 */
export function useTimeline<S extends VersionedState, F extends TimedFrame<S>>(framesFor: (shown: F | null, next: S, reduced: boolean) => F[]) {
  const reduced = useReducedMotion() ?? false
  const reducedNow = useRef(reduced)
  reducedNow.current = reduced
  const [shown, setShown] = useState<Shown<F> | null>(null)
  const queue = useRef<Shown<F>[]>([])
  const newest = useRef<F | null>(null)
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
    (state: S) => {
      const last = newest.current
      if (last && last.state.game_id === state.game_id && last.state.version > state.version) return
      const at = performance.now()
      const frames = framesFor(last, state, reducedNow.current)
      for (const frame of frames) queue.current.push({ frame, at })
      newest.current = frames.at(-1) ?? last
      pump()
    },
    [pump, framesFor],
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
