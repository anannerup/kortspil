import { cardName, type Rank, type Suit } from "./suits.ts"

/**
 * A card as the server sends it: rank + suit, e.g. "2C", "TD", "QS", "AH";
 * at es-makker also a joker, "X1"–"X3" (never a playing card's code).
 */
export type CardCode = string

/** Whether the code is one of es-makker's jokers. */
export const isJoker = (code: CardCode) => /^X[1-3]$/.test(code)

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

/** A card in words: "hjerter 5", "spar dame", "joker". */
export function cardLabel(code: CardCode): string {
  if (isJoker(code)) return "joker"
  const { suit, rank } = parseCardCode(code)
  return cardName(suit, rank)
}
