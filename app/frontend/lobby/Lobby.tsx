import type { Rules } from "~/table/messages"
import { rulesSummary } from "~/table/texts"
import { tablePaths, type LobbyTable } from "./messages"
import { PostForm } from "./PostForm"
import { Seats, statusLabel } from "./Seats"
import { TableKindPill } from "./TableKindPill"
import { TableSettingsFields } from "./TableSettingsFields"
import { useLobbyTables } from "./useLobbyTables"
import "./lobby.css"

export interface LobbyProps {
  practiceTablesPath: string
  tablesPath: string
  standardRules: Rules
  initialTables: LobbyTable[]
  userId: number
  /** The bord the user sits at, if any: they can sit at only one. */
  currentTablePath: string | null
}

/**
 * The lobby: the open and password tables, live from LobbyChannel, and a
 * form to start a table. The host picks the rules, starting from the
 * "Standard hjerterfri" preset the server sends, and the table type, then
 * opens a table for others to join or a practice table against three bots.
 * The server checks it all.
 */
export function Lobby({ practiceTablesPath, tablesPath, standardRules, initialTables, userId, currentTablePath }: LobbyProps) {
  const { tables } = useLobbyTables(initialTables)

  return (
    <div className="lobby">
      <h1>Kortspil</h1>

      {currentTablePath && (
        <p className="lobby-current">
          Du sidder ved et bord. <a href={currentTablePath}>Tilbage til bordet</a>
        </p>
      )}

      <section className="lobby-section">
        <h2>Borde</h2>
        {tables.length === 0 ? (
          <p>Ingen borde lige nu. Opret et nedenfor.</p>
        ) : (
          <ul className="lobby-tables">
            {tables.map((table) => (
              <TableEntry key={table.id} table={table} userId={userId} />
            ))}
          </ul>
        )}
      </section>

      <section className="lobby-section">
        <h2>Nyt bord</h2>
        <NewTableForm tablesPath={tablesPath} practiceTablesPath={practiceTablesPath} standardRules={standardRules} />
      </section>
    </div>
  )
}

function TableEntry({ table, userId }: { table: LobbyTable; userId: number }) {
  return (
    <li className="lobby-table">
      <div className="lobby-table-head">
        <a href={tablePaths(table.id).table}>Bord {table.id}</a>
        <TableKindPill kind={table.kind} />
        <span>Vært: {table.host}</span>
        <span className="lobby-status">{statusLabel(table)}</span>
      </div>
      <p className="lobby-rules-summary">{rulesSummary(table.rules)}</p>
      <Seats table={table} userId={userId} />
    </li>
  )
}

function NewTableForm({ tablesPath, practiceTablesPath, standardRules }: { tablesPath: string; practiceTablesPath: string; standardRules: Rules }) {
  return (
    <PostForm action={tablesPath} className="lobby-rules">
      <TableSettingsFields rules={standardRules} kind="open" />
      <div className="lobby-actions">
        <button type="submit" className="btn btn-primary">
          Opret bord
        </button>
        <button type="submit" className="btn btn-secondary" formAction={practiceTablesPath} formNoValidate>
          Øvebord
        </button>
      </div>
      <p className="hint">
        Et bord venter på fire spillere; du kan sætte bots på de tomme pladser og starter spillet, når alle pladser er besat. Et øvebord spiller du alene
        mod tre bots, og bordtypen gælder ikke for det.
      </p>
    </PostForm>
  )
}
