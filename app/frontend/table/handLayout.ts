/**
 * Where each card of your hand lies, as a transform from the middle of the
 * hand row. Pure: the hand only animates between these spots (transform and
 * opacity), so nothing is laid out or measured while cards move.
 *
 * Cards are drawn BIG times the card width and only ever scaled down, so
 * they stay sharp in the row.
 */
export interface Spot {
  x: number
  y: number
  rotate: number
  scale: number
}

/** The hand row's width and the card width (--cw), in px. */
export interface HandSize {
  width: number
  cw: number
}

export const BIG = 1.12
const RATIO = 1.43 // card height / width
const STEP = 0.38 // fan: each card shows this much of the one under it
const PAD = 0.18 // fan: space above the cards
const TILT = 3.2 // fan: degrees per card from the middle
const ARC = 1.1 // fan: px per card² the outer cards sink
const PIVOT = 1.1 // fan: the cards turn about a point this many card heights below their centre
const GAP = 0.14 // row: space between cards
const EDGE = 24 // row: space left at the sides

/** The fan: overlapping, tilted, and the size of a normal card. */
export function fanSpots(count: number, { cw }: HandSize): Spot[] {
  const scale = 1 / BIG
  const height = cw * RATIO
  const shrink = (cw * BIG * RATIO - height) / 2 // the drawn card is taller than it looks
  const mid = (count - 1) / 2
  return Array.from({ length: count }, (_, index) => {
    const offset = index - mid
    const turn = (offset * TILT * Math.PI) / 180
    return {
      x: offset * STEP * cw + Math.sin(turn) * PIVOT * height,
      y: PAD * cw - shrink + offset * offset * ARC + (1 - Math.cos(turn)) * PIVOT * height,
      rotate: offset * TILT,
      scale,
    }
  })
}

/** The picked suit: big, upright, side by side, and the whole suit fits. */
export function rowSpots(count: number, { width, cw }: HandSize): Spot[] {
  const drawn = cw * BIG
  const card = Math.min(drawn, (width - EDGE - (count - 1) * GAP * cw) / count)
  const scale = card / drawn
  const step = card + GAP * cw
  const mid = (count - 1) / 2
  return Array.from({ length: count }, (_, index) => ({
    x: (index - mid) * step,
    y: -(drawn * RATIO * (1 - scale)) / 2,
    rotate: 0,
    scale,
  }))
}
