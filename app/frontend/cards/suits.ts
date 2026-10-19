// Card data ported from the Hjerterfri design system
// (https://claude.ai/artifact/3jSKXTctgM3g9yLPKpyaWe). Suit icons are inline
// SVG paths drawn with currentColor; never emoji.

export type Suit = "C" | "D" | "S" | "H"
/** 2–14, where 11–14 are J, Q, K, A. */
export type Rank = 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14

interface SuitInfo {
  name: string
  red: boolean
  path: string
}

export const SUITS: Record<Suit, SuitInfo> = {
  C: {
    name: "klør",
    red: false,
    path: "M12 2.5a4.2 4.2 0 0 0-4 5.4A4.2 4.2 0 1 0 9.8 16c.7 0 1.3-.2 1.8-.5-.3 2.3-1.3 4.1-2.9 5.3h6.6c-1.6-1.2-2.6-3-2.9-5.3.5.3 1.1.5 1.8.5A4.2 4.2 0 1 0 16 7.9a4.2 4.2 0 0 0-4-5.4z",
  },
  D: { name: "ruder", red: true, path: "M12 1.8 20.2 12 12 22.2 3.8 12z" },
  S: {
    name: "spar",
    red: false,
    path: "M12 1.8S3.6 8.6 3.6 13.6c0 2.8 2 4.5 4.3 4.5 1.5 0 2.6-.6 3.3-1.6-.3 2-1.3 3.6-2.7 4.5h7c-1.4-.9-2.4-2.5-2.7-4.5.7 1 1.8 1.6 3.3 1.6 2.3 0 4.3-1.7 4.3-4.5 0-5-8.4-11.8-8.4-11.8z",
  },
  H: {
    name: "hjerter",
    red: true,
    path: "M12 21.2s-8.6-5.2-10-10.6C1 6.8 3.4 3.4 6.9 3.4c2.2 0 3.8 1.3 5.1 3.1 1.3-1.8 2.9-3.1 5.1-3.1 3.5 0 5.9 3.4 4.9 7.2-1.4 5.4-10 10.6-10 10.6z",
  },
}

const LETTERS: Partial<Record<Rank, string>> = { 11: "J", 12: "Q", 13: "K", 14: "A" }
const RANK_NAMES: Partial<Record<Rank, string>> = { 11: "knægt", 12: "dame", 13: "konge", 14: "es" }

export function rankLabel(rank: Rank): string {
  return LETTERS[rank] ?? String(rank)
}

/** Accessible name, e.g. "spar dame", "hjerter 10". */
export function cardName(suit: Suit, rank: Rank): string {
  return `${SUITS[suit].name} ${RANK_NAMES[rank] ?? String(rank)}`
}
