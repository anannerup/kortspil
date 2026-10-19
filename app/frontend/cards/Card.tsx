import type { CSSProperties } from "react"
import { SuitIcon, cx } from "./SuitIcon"
import { SUITS, cardName, rankLabel, type Rank, type Suit } from "./suits"
import "./cards.css"

export type CardSize = "sm" | "md" | "lg"
export type CardState = "idle" | "playable" | "selected" | "disabled"

export interface CardProps {
  suit: Suit
  rank: Rank
  /** sm 56px · md 84px · lg 112px; height is width × 1.43. */
  size?: CardSize
  state?: CardState
  /** Gold ring for a card just received. */
  isNew?: boolean
  /** Makes the card a button; without it the card is an image. */
  onClick?: () => void
  className?: string
  style?: CSSProperties
}

/** One playing card, ported from the Hjerterfri design system. */
export function Card({ suit, rank, size = "md", state = "idle", isNew, onClick, className, style }: CardProps) {
  const label = rankLabel(rank)
  const isFace = rank >= 11 && rank <= 13
  const classes = cx(
    "hf-card",
    `hf-card-${size}`,
    SUITS[suit].red ? "hf-red" : "hf-black",
    `is-${state}`,
    isNew && "is-new",
    className,
  )
  const ariaLabel =
    cardName(suit, rank) + (state === "selected" ? ", valgt" : "") + (state === "disabled" ? ", kan ikke spilles" : "")

  const face = (
    <>
      <span className="hf-idx hf-idx-tl">
        <span className="hf-rank">{label}</span>
        <SuitIcon suit={suit} />
      </span>
      <span className={cx("hf-pip", isFace && "hf-pip-face")}>
        {isFace ? <span className="hf-face-letter">{label}</span> : null}
        <SuitIcon suit={suit} />
      </span>
      <span className="hf-idx hf-idx-br">
        <span className="hf-rank">{label}</span>
        <SuitIcon suit={suit} />
      </span>
    </>
  )

  if (onClick) {
    return (
      <button
        type="button"
        className={classes}
        style={style}
        onClick={onClick}
        disabled={state === "disabled"}
        aria-label={ariaLabel}
        aria-pressed={state === "selected" ? true : undefined}
      >
        {face}
      </button>
    )
  }

  return (
    <div className={classes} style={style} role="img" aria-label={ariaLabel}>
      {face}
    </div>
  )
}
