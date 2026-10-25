import type { CSSProperties } from "react"
import { cx } from "./SuitIcon"
import type { CardSize, CardState } from "./Card"
import "./cards.css"

/** A five-pointed star, drawn with currentColor like the suit icons; never emoji. */
const STAR = "M12 1.6l3.1 6.6 7.2.9-5.3 5 1.4 7.1L12 17.7l-6.4 3.5 1.4-7.1-5.3-5 7.2-.9z"

function Star({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={cx("hf-suit", className)} aria-hidden="true" focusable="false">
      <path d={STAR} />
    </svg>
  )
}

export interface JokerProps {
  size?: CardSize
  state?: CardState
  /** Gold ring for a card just received. */
  isNew?: boolean
  /** Makes the joker a button; without it the joker is an image. */
  onClick?: () => void
  className?: string
  style?: CSSProperties
}

/**
 * A joker (es-makker's deck has three), on the same card face as the
 * playing cards: a star and "JOKER" in the corners, a big star and the
 * word in the middle. Like a playing card it can be a button.
 */
export function Joker({ size = "md", state = "idle", isNew, onClick, className, style }: JokerProps) {
  const classes = cx("hf-card", `hf-card-${size}`, "hf-joker", `is-${state}`, isNew && "is-new", className)
  const label = "joker" + (state === "selected" ? ", valgt" : "") + (state === "disabled" ? ", kan ikke spilles" : "")
  const face = (
    <>
      <span className="hf-idx hf-idx-tl">
        <Star />
        <span className="hf-joker-index">JOKER</span>
      </span>
      <span className="hf-pip hf-joker-pip">
        <Star className="hf-joker-star" />
        <span className="hf-joker-word">Joker</span>
      </span>
      <span className="hf-idx hf-idx-br">
        <Star />
        <span className="hf-joker-index">JOKER</span>
      </span>
    </>
  )
  if (onClick) {
    return (
      <button type="button" className={classes} style={style} onClick={onClick} disabled={state === "disabled"} aria-label={label} aria-pressed={state === "selected" ? true : undefined}>
        {face}
      </button>
    )
  }
  return (
    <div className={classes} style={style} role="img" aria-label={label}>
      {face}
    </div>
  )
}
