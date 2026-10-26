import { memo, type MutableRefObject } from "react"
import { CardBack } from "~/cards"
import { csrfToken } from "~/lobby/PostForm"
import type { Position } from "../Trick"

/** Another seat's hand: card backs at the edge of the felt; played cards fly from here. Renders only when the count changes. */
export const OpponentStack = memo(function OpponentStack(props: {
  anchor: (element: HTMLElement | null) => void
  position: Exclude<Position, "south">
  name: string
  count: number
}) {
  const { anchor, position, name, count } = props
  return (
    <div ref={anchor} className={`table-stack table-stack-${position}`} aria-label={`${name}: ${count} kort`}>
      {Array.from({ length: count }, (_, index) => (
        <CardBack key={index} size="sm" />
      ))}
    </div>
  )
})

/** Over the felt: why your last move was refused (it fades), and the tur-ur's warning on your turn. */
export function TableToasts({ notice, warning }: { notice: string | null; warning: string | null }) {
  return (
    <>
      <p className={`table-toast${notice ? "" : " is-hidden"}`} role="alert">
        {notice}
      </p>
      {warning && (
        <p className="table-toast table-toast-warning" role="alert">
          {warning}
        </p>
      )}
    </>
  )
}

/**
 * The hidden form that stands you up from the bord. After the spil
 * everyone sits at the new bord in the lobby (`next`): leaving is standing
 * up from that one.
 */
export function LeaveForm({ formRef, next, departurePath }: { formRef: MutableRefObject<HTMLFormElement | null>; next: string | null; departurePath: string }) {
  return (
    <form ref={formRef} method="post" action={next ? `${next}/departure` : departurePath} hidden>
      <input type="hidden" name="authenticity_token" value={csrfToken()} />
    </form>
  )
}
