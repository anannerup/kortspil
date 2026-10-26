import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react"
import type { CardCode } from "~/cards"
import type { HandSize } from "../handLayout"
import type { SeatIndex, TrickPlay } from "../messages"
import { POSITIONS, type Position } from "../Trick"

/**
 * Elements by key, for measuring where a card flies from or to. The ref
 * callbacks are stable per key, so React never detaches them on re-render,
 * and the object itself is stable too.
 */
export function useAnchors<K>() {
  const [anchors] = useState(() => {
    const elements = new Map<K, HTMLElement>()
    const refs = new Map<K, (element: HTMLElement | null) => void>()
    return {
      get: (key: K) => elements.get(key),
      ref: (key: K) => {
        let callback = refs.get(key)
        if (!callback) {
          callback = (element) => {
            if (element) elements.set(key, element)
            else elements.delete(key)
          }
          refs.set(key, callback)
        }
        return callback
      },
    }
  })
  return anchors
}

/**
 * What the shared stik (Trick) needs from a page, the same at every game:
 * where each seat sits seen from you, and where a played card flies from
 * (your card from where you tapped it, `playedFrom`; another seat's from
 * its hand at the edge of the felt, `seats`). The page keeps `playedFrom`
 * filled as you play and clears it with each new runde.
 */
export function useTrickAnchors(me: SeatIndex) {
  const seats = useAnchors<SeatIndex>()
  const playedFrom = useRef(new Map<CardCode, DOMRect>())
  // Stable per seat, so the memoised stik only renders when its frame changes.
  const positionOf = useCallback((seat: SeatIndex): Position => POSITIONS[(seat - me + 4) % 4] ?? "south", [me])
  const seatRect = useCallback((seat: SeatIndex) => seats.get(seat)?.getBoundingClientRect() ?? null, [seats])
  const flightSource = useCallback(
    (trickPlay: TrickPlay) => {
      const own = trickPlay.seat === me ? playedFrom.current.get(trickPlay.card) : undefined
      if (own) return { rect: own }
      const rect = seatRect(trickPlay.seat)
      return rect ? { rect, scale: 0.45 } : null
    },
    [me, seatRect],
  )
  return { seats, playedFrom, positionOf, seatRect, flightSource }
}

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches)
  useEffect(() => {
    const list = window.matchMedia(query)
    const change = () => setMatches(list.matches)
    change()
    list.addEventListener("change", change)
    return () => list.removeEventListener("change", change)
  }, [query])
  return matches
}

/** The hand row's width and the card width, measured before paint and on resize. */
export function useHandSize() {
  const sizer = useRef<HTMLDivElement | null>(null)
  const row = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState<HandSize | null>(null)
  useLayoutEffect(() => {
    const measure = () => {
      const width = row.current?.clientWidth ?? 0
      const cw = sizer.current?.offsetWidth ?? 0
      setSize((current) => (current && current.width === width && current.cw === cw ? current : { width, cw }))
    }
    measure()
    const observer = new ResizeObserver(measure)
    if (row.current) observer.observe(row.current)
    if (sizer.current) observer.observe(sizer.current)
    return () => observer.disconnect()
  }, [])
  return [size, sizer, row] as const
}
