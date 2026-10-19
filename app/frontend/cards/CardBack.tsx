import type { CSSProperties } from "react"
import { cx } from "./SuitIcon"
import "./cards.css"

export interface CardBackProps {
  /** xs 34px (opponents' hands) · sm 56px · md 84px · lg 112px */
  size?: "xs" | "sm" | "md" | "lg"
  className?: string
  style?: CSSProperties
}

/**
 * The back of a card. Decorative only: whatever shows it carries the card
 * count for assistive tech.
 */
export function CardBack({ size = "md", className, style }: CardBackProps) {
  return <div className={cx("hf-back", size !== "md" && `hf-back-${size}`, className)} style={style} aria-hidden="true" />
}
