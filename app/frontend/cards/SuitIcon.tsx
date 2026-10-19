import { SUITS, type Suit } from "./suits"

interface SuitIconProps {
  suit: Suit
  className?: string
}

export function SuitIcon({ suit, className }: SuitIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={cx("hf-suit", className)}
      aria-hidden="true"
      focusable="false"
    >
      <path d={SUITS[suit].path} />
    </svg>
  )
}

export function cx(...names: Array<string | false | null | undefined>): string {
  return names.filter(Boolean).join(" ")
}
