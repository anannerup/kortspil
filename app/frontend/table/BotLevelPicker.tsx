import type { BotLevel } from "~/lobby/messages"
import { BOT_LEVEL_NAMES, BOT_LEVELS, botKind } from "./texts"

/**
 * The vært's choice of a bot's level: Let, Mellem or Svær. Before the
 * spil (the seat list) and between spil (the end screen); the server
 * refuses it during a spil. `compact` names only the level, beside a
 * "+ Bot" button.
 */
export function BotLevelPicker(props: { level: BotLevel; botName: string; disabled?: boolean; compact?: boolean; onChange: (level: BotLevel) => void }) {
  const { level, botName, disabled = false, compact = false, onChange } = props
  return (
    <select
      className="bot-level-picker"
      aria-label={`Niveau for ${botName}`}
      value={level}
      disabled={disabled}
      onChange={(event) => onChange(event.target.value as BotLevel)}
    >
      {BOT_LEVELS.map((option) => (
        <option key={option} value={option}>
          {compact ? BOT_LEVEL_NAMES[option] : botKind(option)}
        </option>
      ))}
    </select>
  )
}
