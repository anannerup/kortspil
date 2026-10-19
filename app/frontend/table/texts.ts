// Danish texts for the table. Labels only: no rules are decided here.
import type { PassDirection, RejectionReason } from "./messages"

export const REJECTIONS: Record<RejectionReason, string> = {
  round_complete: "Runden er slut.",
  unknown_intent: "Det kan du ikke her.",
  not_your_turn: "Det er ikke din tur.",
  card_not_in_hand: "Det kort har du ikke.",
  must_lead_two_of_clubs: "Du skal spille klør 2 ud.",
  must_follow_suit: "Du skal bekende kulør.",
  no_points_on_first_trick: "Du må ikke give point i første stik.",
  hearts_not_broken: "Hjerter er ikke brudt endnu.",
  not_passing: "Der byttes ikke kort nu.",
  already_passed: "Du har allerede givet dine kort.",
  wrong_card_count: "Vælg præcis 3 kort.",
  duplicate_cards: "Vælg 3 forskellige kort.",
  passing_not_complete: "Vent til alle har givet kort.",
}

/** The pass instruction for the runde. */
export const PASS_INSTRUCTIONS: Record<PassDirection, string> = {
  left: "Giv 3 kort til venstre",
  right: "Giv 3 kort til højre",
  across: "Giv 3 kort til spilleren overfor",
  none: "Ingen bytning denne runde",
}

/** The direction in the score sheet. */
export const DIRECTION_LABELS: Record<PassDirection, string> = {
  left: "Venstre",
  right: "Højre",
  across: "Overfor",
  none: "Ingen",
}

export const pointsLabel = (points: number) => `${points} point`

/** "Anna", "Anna og Bot 1", "Anna, Bot 1 og Bot 2" */
export function joinNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? ""
  return `${names.slice(0, -1).join(", ")} og ${names[names.length - 1]}`
}
