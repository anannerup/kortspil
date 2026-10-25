import type { TableState } from "./messages"
import { FLY_MS, PAUSE_MS, SWEEP_MS } from "./Trick"

// The server answers at once (bots don't wait), so several states can
// arrive together. The table shows them one at a time, at the pace of the
// animations: a card has landed before the next flies, and a completed stik
// rests and sweeps before the next stik starts.
const AFTER_PLAY_MS = FLY_MS + 60
const AFTER_TRICK_MS = FLY_MS + PAUSE_MS + SWEEP_MS

const cards = (plays: { card: string }[]) => plays.map((play) => play.card).join(",")

/** How long `next` should stay on screen before a later state replaces it. */
export function holdAfter(previous: TableState | null, next: TableState): number {
  if (!previous || previous.game_id !== next.game_id || previous.round_number !== next.round_number) return 0
  const before = previous.view
  const after = next.view
  if (cards(after.last_trick) !== cards(before.last_trick) && after.last_trick.length > 0) return AFTER_TRICK_MS
  if (after.current_trick.length > before.current_trick.length) return AFTER_PLAY_MS
  return 0
}
