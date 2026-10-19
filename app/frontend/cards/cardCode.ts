import type { Rank, Suit } from "./suits"

/** A card as the server sends it: rank + suit, e.g. "2C", "TD", "QS", "AH". */
export type CardCode = string

const RANKS: Record<string, Rank> = {
  "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
  T: 10, J: 11, Q: 12, K: 13, A: 14,
}

function isSuit(value: string): value is Suit {
  return value === "C" || value === "D" || value === "S" || value === "H"
}

export function parseCardCode(code: CardCode): { suit: Suit; rank: Rank } {
  const rank = RANKS[code.charAt(0)]
  const suit = code.charAt(1)
  if (rank === undefined || !isSuit(suit) || code.length !== 2) throw new Error(`Not a card code: ${code}`)

  return { suit, rank }
}
