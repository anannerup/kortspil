import { Card, type CardSize, type CardState } from "./Card"
import { isJoker, parseCardCode, type CardCode } from "./cardCode"
import { Joker } from "./Joker"

/**
 * Any card the server sends by its code, a joker ("X1"–"X3", es-makker)
 * or a playing card; with `onClick` a button.
 */
export function CardFace(props: { code: CardCode; size?: CardSize; state?: CardState; isNew?: boolean; onClick?: () => void; className?: string }) {
  const { code, ...rest } = props
  if (isJoker(code)) return <Joker {...rest} />
  return <Card {...parseCardCode(code)} {...rest} />
}
