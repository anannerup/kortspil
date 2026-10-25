import type { SeatIndex, TableState, TrickPlay } from "./messages"

/**
 * The table's timeline: what is on screen, and for how long.
 *
 * The server answers at once (bots don't wait) and every state is the
 * truth as of now. The table plays those states back as frames at the
 * pace of the animations: a card lands before the next flies, and a
 * completed stik rests, then sweeps to its winner, before the points,
 * "Sidste stik", the next stik or the runde result show. Pure: a frame is
 * derived from the frame before it and the next state.
 */

// Timings (ms). The single table of them; Trick animates within these.
export const FLY_MS = 440
export const PAUSE_MS = 950
export const SWEEP_MS = 480
const PLAY_HOLD_MS = FLY_MS + 60
const PLAY_HOLD_REDUCED_MS = 250

/** The stik that last left the table: what "Sidste stik" shows. */
export interface LastTrick {
  plays: TrickPlay[]
  winner: SeatIndex | null
}

export interface Frame {
  /** What everything around the stik shows (hand, tags, points, overlays). */
  state: TableState
  /** The cards in the middle. */
  trick: TrickPlay[]
  /** Set while the stik slides off to its winner. */
  sweepTo: SeatIndex | null
  lastTrick: LastTrick
  /** How long this frame stays before the next one may show. */
  hold: number
}

const cards = (plays: TrickPlay[]) => plays.map((play) => play.card).join(",")
const lastOf = (state: TableState): LastTrick => ({ plays: state.view.last_trick, winner: state.view.last_trick_winner })

/** The frames that take the table from `shown` to `next`, in order. */
export function framesFor(shown: Frame | null, next: TableState, reduced: boolean): Frame[] {
  const settled: Frame = { state: next, trick: next.view.current_trick, sweepTo: null, lastTrick: lastOf(next), hold: 0 }
  if (!shown) return [settled]
  const before = shown.state
  const sameRunde = before.game_id === next.game_id && before.round_number === next.round_number
  if (!sameRunde) return [settled]

  const view = next.view
  const completed = view.last_trick.length > 0 && cards(view.last_trick) !== cards(before.view.last_trick)
  if (completed) {
    if (reduced) return [settled]
    // While the stik lies on the table, the rest of the table still shows
    // how things stood before it: its points, no runde result, nobody to act.
    const onTable: TableState = {
      ...next,
      status: before.status,
      points_taken: before.points_taken,
      score: before.score,
      view: { ...view, phase: "playing", points: before.view.points, to_act: null, legal_moves: [] },
    }
    const resting = { state: onTable, trick: view.last_trick, sweepTo: null, lastTrick: shown.lastTrick, hold: FLY_MS + PAUSE_MS }
    const leaving = { ...resting, sweepTo: view.last_trick_winner, hold: SWEEP_MS }
    return [resting, leaving, settled]
  }

  if (view.current_trick.length > shown.trick.length) return [{ ...settled, hold: reduced ? PLAY_HOLD_REDUCED_MS : PLAY_HOLD_MS }]
  return [settled]
}
