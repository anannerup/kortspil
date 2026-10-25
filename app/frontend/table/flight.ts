import { useLayoutEffect, type RefObject } from "react"
import { animate } from "motion/react"

/** Where a card flies in from: a screen rect and the scale it starts at there. */
export interface FlightSource {
  rect: DOMRect
  /** Leave out to start at the rect's own size. */
  scale?: number
}

const center = (rect: DOMRect) => ({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 })

/**
 * On mount, slides the element from `from` to where it lies, with transform
 * only. The element must carry no other transform of its own (wrap it).
 */
export function useFlyIn(
  ref: RefObject<HTMLElement | null>,
  from: () => FlightSource | null,
  transition: { duration: number; ease: readonly number[] },
) {
  useLayoutEffect(() => {
    const element = ref.current
    const source = from()
    if (!element || !source) return
    const here = center(element.getBoundingClientRect())
    const there = center(source.rect)
    const rect = element.getBoundingClientRect()
    const scale = source.scale ?? (rect.width > 0 ? source.rect.width / rect.width : 1)
    const controls = animate(
      element,
      { x: [there.x - here.x, 0], y: [there.y - here.y, 0], scale: [scale, 1] },
      { duration: transition.duration, ease: [...transition.ease] as [number, number, number, number] },
    )
    return () => controls.stop()
  }, []) // On mount only: a card flies in once.
}
