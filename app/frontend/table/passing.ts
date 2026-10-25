import type { PassDirection, SeatIndex } from "./messages"

const OFFSETS: Record<PassDirection, number> = { left: 1, right: 3, across: 2, none: 0 }

/** Who gets this seat's pass: seats sit clockwise, left is the next seat. */
export function receiverOf(seat: SeatIndex, direction: PassDirection): SeatIndex {
  return (seat + OFFSETS[direction]) % 4
}

/** Who passes to this seat. */
export function giverOf(seat: SeatIndex, direction: PassDirection): SeatIndex {
  return (seat - OFFSETS[direction] + 4) % 4
}
