import { Card, type CardSize, type CardState } from "./Card"
import { isJoker, parseCardCode, type CardCode } from "./cardCode"
import { Joker } from "./Joker"

/**
 * Any card the server sends by its code, a joker ("X1"–"X3", es-makker)
 * or a playing card. A joker is never a button yet.
 */
export function CardFace({ code, size, state, className }: { code: CardCode; size?: CardSize; state?: CardState; className?: string }) {
  if (isJoker(code)) return <Joker size={size} className={className} />
  return <Card {...parseCardCode(code)} size={size} state={state} className={className} />
}
