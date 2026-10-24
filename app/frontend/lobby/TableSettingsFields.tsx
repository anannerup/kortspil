import { useState } from "react"
import type { RuleToggle, Rules } from "~/table/messages"
import { RULE_LABELS } from "~/table/texts"
import type { TableKind } from "./messages"

const KINDS: { kind: TableKind; label: string; hint: string }[] = [
  { kind: "open", label: "Åbent bord", hint: "Vises i lobbyen. Alle kan sætte sig." },
  { kind: "password", label: "Med adgangskode", hint: "Vises i lobbyen med en lås. Man skal kende adgangskoden for at sætte sig." },
  { kind: "private", label: "Privat bord", hint: "Vises ikke i lobbyen. Kun dem, der får linket, kan finde bordet." },
]

/**
 * The fields a vært fills in for a bord: the rules (end score and house
 * rules) and the table type, with a password for a password table. Used by
 * the lobby's new-table form and the waiting room's settings. Field names
 * match RulesParams and the tables controllers; the server checks it all.
 */
export function TableSettingsFields(props: {
  rules: Rules
  kind: TableKind
  /** The table has a password already: a blank field keeps it. */
  hasPassword?: boolean
}) {
  const { rules, hasPassword = false } = props
  const [kind, setKind] = useState<TableKind>(props.kind)
  const toggles = Object.keys(RULE_LABELS) as RuleToggle[]

  return (
    <>
      <fieldset>
        <legend>Regler</legend>
        <label>
          Spillet slutter ved{" "}
          <input type="number" name="rules[end_score]" min={1} step={1} required defaultValue={rules.end_score} inputMode="numeric" /> point
        </label>
        {toggles.map((toggle) => (
          <label key={toggle} className="lobby-check">
            <input type="hidden" name={`rules[${toggle}]`} value="0" />
            <input type="checkbox" name={`rules[${toggle}]`} value="1" defaultChecked={rules[toggle]} /> {RULE_LABELS[toggle]}
          </label>
        ))}
        <p className="hint">Reglerne kan ikke ændres, når første runde er givet.</p>
      </fieldset>

      <fieldset>
        <legend>Bordtype</legend>
        {KINDS.map((option) => (
          <label key={option.kind} className="lobby-check">
            <input type="radio" name="kind" value={option.kind} checked={kind === option.kind} onChange={() => setKind(option.kind)} />{" "}
            <span>
              <strong>{option.label}</strong>
              <span className="hint lobby-check-hint">{option.hint}</span>
            </span>
          </label>
        ))}
        {kind === "password" && (
          <div className="field lobby-password">
            <label htmlFor="table-password">Adgangskode</label>
            <input
              id="table-password"
              type="text"
              name="password"
              autoComplete="off"
              required={!hasPassword}
              placeholder={hasPassword ? "Lad stå tom for at beholde den" : undefined}
            />
            <p className="hint">Fortæl den til dem, du vil spille med.</p>
          </div>
        )}
      </fieldset>
    </>
  )
}
