import type { SeatIndex, TrickPlay } from "~/table/messages"
import { FLY_MS, PAUSE_MS, SWEEP_MS } from "../table/timeline.ts"
import type { EsmakkerTableState, PlayView, SolPlayView } from "./messages"

/**
 * The es-makker table's timeline, as hjerterfri's (table/timeline.ts): the
 * server's states played back as frames at the pace of the card
 * animations. A card lands before the next flies; a completed stik rests,
 * then sweeps to its winner, before the next stik or the runde result
 * show. Pure: a frame is derived from the frame before it and the next
 * state.
 */

const PLAY_HOLD_MS = FLY_MS + 60
const PLAY_HOLD_REDUCED_MS = 250

export interface EsmakkerFrame {
  /** What everything around the stik shows (hand, tags, panel, overlays). */
  state: EsmakkerTableState
  /** The cards in the middle. */
  trick: TrickPlay[]
  /** Set while the stik slides off to its winner. */
  sweepTo: SeatIndex | null
  /** How long this frame stays before the next one may show. */
  hold: number
}

const cards = (plays: TrickPlay[]) => plays.map((play) => play.card).join(",")

/** The frames that take the table from `shown` to `next`, in order. */
export function esmakkerFrames(shown: EsmakkerFrame | null, next: EsmakkerTableState, reduced: boolean): EsmakkerFrame[] {
  const play = next.view.play
  const settled: EsmakkerFrame = { state: next, trick: play?.current_trick ?? [], sweepTo: null, hold: 0 }
  if (!shown || !play) return [settled]
  const before = shown.state
  const sameRunde = before.game_id === next.game_id && before.round_number === next.round_number
  if (!sameRunde) return [settled]

  const lastBefore = before.view.play?.last_trick ?? []
  const completed = play.last_trick.length > 0 && cards(play.last_trick) !== cards(lastBefore)
  if (completed) {
    if (reduced) return [settled]
    // While the stik lies on the table, the rest of the table shows how
    // things stood before it: its stik counts, no result, nobody to act.
    const onTable: EsmakkerTableState = {
      ...next,
      status: before.status,
      score: before.score,
      next_path: undefined,
      view: {
        ...next.view,
        phase: "playing",
        to_act: null,
        result: null,
        play: restingPlay(play, before.view.play),
      },
    }
    const resting = { state: onTable, trick: play.last_trick, sweepTo: null, hold: FLY_MS + PAUSE_MS }
    const leaving = { ...resting, sweepTo: play.last_trick_winner, hold: SWEEP_MS }
    return [resting, leaving, settled]
  }

  if (play.current_trick.length > shown.trick.length) return [{ ...settled, hold: reduced ? PLAY_HOLD_REDUCED_MS : PLAY_HOLD_MS }]
  return [settled]
}

/** The play while a completed stik still lies on the table: nothing to play, and the stik counts (and who is væltet at sol) as before it. */
function restingPlay(play: PlayView | SolPlayView, before: PlayView | SolPlayView | null): PlayView | SolPlayView {
  const tricks_won = before?.tricks_won ?? play.tricks_won
  if (play.kind === "sol") return { ...play, legal_moves: [], tricks_won, vaeltet: before?.kind === "sol" ? before.vaeltet : play.vaeltet }
  return { ...play, legal_moves: [], tricks_won, side_stik: before?.kind === "sol" ? null : (before?.side_stik ?? null) }
}
