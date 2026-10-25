// Danish texts for the table. Labels only: no rules are decided here.
import type { PassDirection, RejectionReason, RuleToggle, Rules } from "./messages"

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
  choosing_moon: "Vent til den, der skød månen, har valgt.",
  not_choosing_moon: "Der er ikke noget at vælge nu.",
  unknown_moon_choice: "Det valg findes ikke.",
  bidding_complete: "Meldingsrunden er slut.",
  bidding_started: "Der er meldt; jernhånd kan kun meldes før første melding.",
  no_jernhaand: "Du har ikke jernhånd.",
  nothing_to_take_over: "Der er intet at overtage.",
  not_sol_melding: "Man kan kun gå med på sol, ren sol, bordlægger og ren bordlægger.",
  det_kan_jeg_selv_or_pas: "Sig \"det kan jeg selv\" eller pas.",
  not_on_ladder: "Den melding findes ikke ved bordet.",
  not_higher: "Du skal melde højere.",
}

/** The names of the house rules, as the host sees them when choosing. */
export const RULE_LABELS: Record<RuleToggle, string> = {
  queen_breaks_hearts: "Spar dame bryder hjerter",
  jack_of_diamonds_minus_ten: "Ruder knægt giver minus 10",
  shooters_choice: "Shooter's choice: den, der skyder månen, vælger 26 til de andre eller −26 til sig selv",
}

/** "Til 100 point · Ruder knægt giver minus 10": the end score and the house rules that are on. */
export function rulesSummary(rules: Rules): string {
  const on = (Object.keys(RULE_LABELS) as RuleToggle[]).filter((toggle) => rules[toggle]).map((toggle) => RULE_LABELS[toggle])
  return [`Til ${rules.end_score} point`, ...(on.length > 0 ? on : ["Ingen husregler"])].join(" · ")
}

/** The pass instruction for the runde. */
export const PASS_INSTRUCTIONS: Record<PassDirection, string> = {
  left: "Giv 3 kort til venstre",
  right: "Giv 3 kort til højre",
  across: "Giv 3 kort til spilleren overfor",
  none: "Ingen bytte denne runde",
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
