import { useEffect, useState } from "react"
import type { SeatInfo } from "./messages"

/**
 * The turn timer as the client shows it. The server sends each seat's
 * seconds left when it builds a state (TurnClock); the client only counts
 * down from when that state arrived. It decides nothing: the server's
 * clock tick is what warns and what makes a seat forladt.
 */
export function secondsLeft(seat: SeatInfo | undefined, receivedAt: number, now: number): number | null {
  if (!seat || seat.seconds_left === null) return null
  return Math.max(0, seat.seconds_left - (now - receivedAt) / 1000)
}

/** performance.now(), refreshed a few times a second while `running`. */
export function useNow(running: boolean): number {
  const [now, setNow] = useState(() => performance.now())
  useEffect(() => {
    if (!running) return
    setNow(performance.now())
    const timer = setInterval(() => setNow(performance.now()), 250)
    return () => clearInterval(timer)
  }, [running])
  return now
}
