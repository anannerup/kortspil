import { useEffect, useState } from "react"
import type { EsmakkerLobbyTable } from "~/lobby/messages"
import type { SetupActions } from "~/table/SetupPanel"
import type { EsmakkerPoints, EsmakkerRules, StakeNumber } from "./messages"
import { PAHAENG_NAMES, POINT_LABELS, STAKE_NUMBERS, amount, esmakkerSettingsFields, movePahaeng, runderLabel } from "./rules"
import "./esmakker.css"

const BANK_WINDOWS = [5, 6, 7, 8, 9, 10]

/**
 * An es-makker bord's rules in the panel before the spil (kept apart from
 * hjerterfri's in SetupPanel): the number of runder (the bord's own rule)
 * and es-makker's GameRules, REGLER §2.0's ⚙️ settings. The vært changes
 * them here, each change saved at once (numbers when the field is left);
 * the server checks every value.
 */
export function EsmakkerRulesSettings({ table, actions }: { table: EsmakkerLobbyTable; actions: SetupActions }) {
  const { rules, runder, kind } = table
  const save = (next: EsmakkerRules, nextRunder: number | null = runder) => void actions.saveSettings(esmakkerSettingsFields(next, nextRunder, kind))
  const savePoints = (points: EsmakkerPoints) => save({ ...rules, points })

  return (
    <>
      <ul className="table-panel-rules setup-rules">
        <li className="setup-end-score">
          <label htmlFor="esmakker-runder">Antal runder</label>
          <NumberField id="esmakker-runder" value={runder ?? 10} whole min={5} max={50} disabled={actions.busy} onSave={(value) => save(rules, value)} />
        </li>
        <li>
          <span className="esmakker-label">Påhæng, højeste først</span>
          <ol className="esmakker-pahaeng">
            {rules.pahaeng_order.map((pahaeng, index) => (
              <li key={pahaeng}>
                <span>
                  {index + 1}. {PAHAENG_NAMES[pahaeng]}
                </span>
                <span className="esmakker-pahaeng-moves">
                  <button type="button" className="setup-chip" aria-label={`${PAHAENG_NAMES[pahaeng]} op`} disabled={index === 0 || actions.busy} onClick={() => save({ ...rules, pahaeng_order: movePahaeng(rules.pahaeng_order, index, -1) })}>
                    ↑
                  </button>
                  <button
                    type="button"
                    className="setup-chip"
                    aria-label={`${PAHAENG_NAMES[pahaeng]} ned`}
                    disabled={index === rules.pahaeng_order.length - 1 || actions.busy}
                    onClick={() => save({ ...rules, pahaeng_order: movePahaeng(rules.pahaeng_order, index, 1) })}
                  >
                    ↓
                  </button>
                </span>
              </li>
            ))}
          </ol>
        </li>
        <li className={rules.joker_trumpable ? "is-on" : undefined}>
          <label className="setup-toggle">
            <input type="checkbox" checked={rules.joker_trumpable} disabled={actions.busy} onChange={(event) => save({ ...rules, joker_trumpable: event.target.checked })} />
            <span>Jokere kan stikkes med trumf</span>
          </label>
        </li>
        <li className={rules.esmakker_banks_first ? "is-on" : undefined}>
          <label className="setup-toggle">
            <input type="checkbox" checked={rules.esmakker_banks_first} disabled={actions.busy} onChange={(event) => save({ ...rules, esmakker_banks_first: event.target.checked })} />
            <span>Esmakkeren må banke først (ved vip)</span>
          </label>
        </li>
        <li className="setup-end-score">
          <label htmlFor="esmakker-bank-window">Bank-vindue</label>
          <span>
            <select id="esmakker-bank-window" className="esmakker-select" value={rules.bank_window} disabled={actions.busy} onChange={(event) => save({ ...rules, bank_window: Number(event.target.value) })}>
              {BANK_WINDOWS.map((seconds) => (
                <option key={seconds} value={seconds}>
                  {seconds}
                </option>
              ))}
            </select>{" "}
            sekunder
          </span>
        </li>
      </ul>
      <details className="esmakker-points">
        <summary>Pointtabel</summary>
        <p className="setup-hint">Indsatsen pr. melding; går den hjem, +1 pr. overstik. Faktorerne ganges oveni.</p>
        <div className="esmakker-points-grid is-editing">
          {STAKE_NUMBERS.map((number) => (
            <PointField key={number} label={`Indsats ${number}`} value={rules.points.stakes[number]} disabled={actions.busy} onSave={(value) => savePoints({ ...rules.points, stakes: { ...rules.points.stakes, [number as StakeNumber]: value } })} />
          ))}
          {POINT_LABELS.map(({ key, label, factor }) => (
            <PointField key={key} label={label} prefix={factor ? "×" : ""} value={rules.points[key]} disabled={actions.busy} onSave={(value) => savePoints({ ...rules.points, [key]: value })} />
          ))}
        </div>
      </details>
    </>
  )
}

/** The rules as everyone else sees them (and in the spil's Regler tab). */
export function EsmakkerRulesSummary({ rules, runder }: { rules: EsmakkerRules; runder: number | null }) {
  return (
    <>
      <ul className="table-panel-rules setup-rules">
        <li className="setup-end-score">Spillet er {runderLabel(runder)}</li>
        <li>Påhæng, højeste først: {rules.pahaeng_order.map((pahaeng) => PAHAENG_NAMES[pahaeng]).join(" > ")}</li>
        <li className={rules.joker_trumpable ? "is-on" : undefined}>
          {rules.joker_trumpable ? "✓" : "–"} Jokere kan stikkes med trumf
        </li>
        <li className={rules.esmakker_banks_first ? "is-on" : undefined}>
          {rules.esmakker_banks_first ? "✓" : "–"} Esmakkeren må banke først (ved vip)
        </li>
        <li>Bank-vindue: {rules.bank_window} sekunder</li>
      </ul>
      <details className="esmakker-points">
        <summary>Pointtabel</summary>
        <dl className="esmakker-points-grid">
          {STAKE_NUMBERS.map((number) => (
            <div key={number}>
              <dt>Indsats {number}</dt>
              <dd>{amount(rules.points.stakes[number])}</dd>
            </div>
          ))}
          {POINT_LABELS.map(({ key, label, factor }) => (
            <div key={key}>
              <dt>{label}</dt>
              <dd>
                {factor ? "×" : ""}
                {amount(rules.points[key])}
              </dd>
            </div>
          ))}
        </dl>
      </details>
    </>
  )
}

/** One point value: saved when the field is left, if it is a positive amount ("1,5" works). */
function PointField(props: { label: string; prefix?: string; value: number; disabled: boolean; onSave: (value: number) => void }) {
  const { label, prefix = "", value, disabled, onSave } = props
  const id = `esmakker-point-${label.replace(/\W+/g, "-").toLowerCase()}`
  return (
    <div>
      <label htmlFor={id}>{label}</label>
      <span>
        {prefix}
        <NumberField id={id} value={value} disabled={disabled} onSave={onSave} />
      </span>
    </div>
  )
}

/** A number field that saves when left (or on Enter), and falls back to the saved value when the entry is not valid. */
function NumberField(props: { id: string; value: number; whole?: boolean; min?: number; max?: number; disabled: boolean; onSave: (value: number) => void }) {
  const { id, value, whole = false, min, max, disabled, onSave } = props
  const [text, setText] = useState(amount(value))
  useEffect(() => setText(amount(value)), [value])

  const commit = () => {
    const next = Number(text.replace(",", "."))
    const valid = Number.isFinite(next) && next > 0 && (!whole || Number.isInteger(next)) && (min === undefined || next >= min) && (max === undefined || next <= max)
    if (!valid) {
      setText(amount(value))
      return
    }
    if (next !== value) onSave(next)
  }

  return (
    <input
      id={id}
      type="text"
      inputMode={whole ? "numeric" : "decimal"}
      className="esmakker-number"
      value={text}
      disabled={disabled}
      onChange={(event) => setText(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.key === "Enter") event.currentTarget.blur()
      }}
    />
  )
}
