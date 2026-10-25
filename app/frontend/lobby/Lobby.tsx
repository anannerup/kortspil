import { rulesSummary } from "~/table/texts"
import { tablePaths, type LobbyTable } from "./messages"
import { PostForm } from "./PostForm"
import { Seats, statusLabel } from "./Seats"
import { TableKindPill } from "./TableKindPill"
import { useLobbyTables } from "./useLobbyTables"
import "./lobby.css"

export interface LobbyProps {
  practiceTablesPath: string
  tablesPath: string
  initialTables: LobbyTable[]
  userId: number
  /** The bord the user sits at, if any: they can sit at only one. */
  currentTablePath: string | null
}

/**
 * The lobby: the open and password tables, live from LobbyChannel, and the
 * buttons to open a bord for others to join or a practice bord against
 * three bots. Both open with the "Standard hjerterfri" rules; the vært
 * chooses the rules and the table type at the table, before the spil.
 */
export function Lobby({ practiceTablesPath, tablesPath, initialTables, userId, currentTablePath }: LobbyProps) {
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
        <NewTable tablesPath={tablesPath} practiceTablesPath={practiceTablesPath} />
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

function NewTable({ tablesPath, practiceTablesPath }: { tablesPath: string; practiceTablesPath: string }) {
  return (
    <>
      <div className="lobby-actions">
        <PostForm action={tablesPath}>
          <button type="submit" className="btn btn-primary">
            Opret bord
          </button>
        </PostForm>
        <PostForm action={practiceTablesPath}>
          <button type="submit" className="btn btn-secondary">
            Øvebord
          </button>
        </PostForm>
      </div>
      <p className="hint">
        Du sætter dig ved bordet og vælger regler og bordtype der. Et bord venter på fire spillere; du kan sætte bots på de tomme pladser og starter
        spillet, når alle pladser er besat. Et øvebord spiller du alene mod tre bots.
      </p>
    </>
  )
}
