import type { RuleToggle, Rules } from "~/table/messages"
import { RULE_LABELS } from "~/table/texts"

/**
 * The lobby placeholder: for now only the practice table. The host picks
 * the rules, starting from the "Standard hjerterfri" preset the server
 * sends; the server checks them.
 */
export function Lobby({ practiceTablesPath, standardRules }: { practiceTablesPath: string; standardRules: Rules }) {
  const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
  const toggles = Object.keys(RULE_LABELS) as RuleToggle[]

  return (
    <main>
      <h1>Kortspil</h1>
      <form method="post" action={practiceTablesPath} className="lobby-rules">
        <input type="hidden" name="authenticity_token" value={csrfToken} />
        <fieldset>
          <legend>Regler</legend>
          <label>
            Spillet slutter ved{" "}
            <input type="number" name="rules[end_score]" min={1} step={1} required defaultValue={standardRules.end_score} /> point
          </label>
          {toggles.map((toggle) => (
            <label key={toggle}>
              <input type="hidden" name={`rules[${toggle}]`} value="0" />
              <input type="checkbox" name={`rules[${toggle}]`} value="1" defaultChecked={standardRules[toggle]} /> {RULE_LABELS[toggle]}
            </label>
          ))}
          <p>Reglerne kan ikke ændres, når første runde er givet.</p>
        </fieldset>
        <button type="submit">Øvebord</button>
      </form>
      <p>Spil hjerterfri mod tre bots.</p>
    </main>
  )
}
