import { esmakkerSummary } from "~/esmakker/rules"
import { GAME_NAMES } from "~/table/setup"
import { rulesSummary } from "~/table/texts"
import type { LobbyTable } from "./messages"
import { PostForm } from "./PostForm"
import { Seats, statusLabel } from "./Seats"
import { TableKindPill } from "./TableKindPill"
import { useLobbyTables } from "./useLobbyTables"
import "./lobby.css"

export interface LobbyProps {
  practiceTablesPath: string
  /** Where "Hjerterfri" makes a new bord (WaitingTablesController#create). */
  waitingTablesPath: string
  initialTables: LobbyTable[]
  userId: number
  /** The bord the user sits at, if any: they can sit at only one. */
  currentTablePath: string | null
}

/**
 * The lobby: the open and password borde, live from LobbyChannel, and a
 * new bord: you pick the game it is for (Hjerterfri or Es-makker), or a
 * practice bord against three bots (hjerterfri). A new bord opens with
 * the game's standard rules; the vært chooses the rules and the table
 * type at the bord, before the spil. Nothing is stored until the spil
 * starts.
 */
export function Lobby({ practiceTablesPath, waitingTablesPath, initialTables, userId, currentTablePath }: LobbyProps) {
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
        <NewTable waitingTablesPath={waitingTablesPath} practiceTablesPath={practiceTablesPath} />
      </section>
    </div>
  )
}

function TableEntry({ table, userId }: { table: LobbyTable; userId: number }) {
  return (
    <li className="lobby-table">
      <div className="lobby-table-head">
        <a href={table.path}>{table.name}</a>
        <TableKindPill kind={table.kind} />
        <span>Vært: {table.host}</span>
        <span className="lobby-status">{statusLabel(table)}</span>
      </div>
      <p className="lobby-rules-summary">
        {GAME_NAMES[table.game]} · {table.game === "esmakker" ? esmakkerSummary(table.rules, table.runder) : rulesSummary(table.rules)}
      </p>
      <Seats table={table} userId={userId} />
    </li>
  )
}

function NewTable({ waitingTablesPath, practiceTablesPath }: { waitingTablesPath: string; practiceTablesPath: string }) {
  return (
    <>
      <p className="lobby-games-lead">Vælg spillet, så sætter du dig ved et nyt bord.</p>
      <div className="lobby-games">
        <PostForm action={waitingTablesPath} className="lobby-game-form">
          <input type="hidden" name="game" value="hjerterfri" />
          <button type="submit" className="lobby-game">
            <span className="lobby-game-name">Hjerterfri</span>
            <span className="lobby-game-hint">Undgå hjerterne og spar dame</span>
          </button>
        </PostForm>
        <PostForm action={waitingTablesPath} className="lobby-game-form">
          <input type="hidden" name="game" value="esmakker" />
          <button type="submit" className="lobby-game">
            <span className="lobby-game-name">Es-makker</span>
            <span className="lobby-game-hint">Meld, kald et es, og find din makker</span>
          </button>
        </PostForm>
      </div>
      <div className="lobby-actions">
        <PostForm action={practiceTablesPath}>
          <button type="submit" className="btn btn-secondary">
            Øvebord
          </button>
        </PostForm>
      </div>
      <p className="hint">
        Ved bordet vælger du regler og bordtype og puffer dine venner. Spillet starter, når alle fire pladser er besat; ved hjerterfri kan du sætte bots på de tomme
        pladser, es-makker spilles af fire mennesker. Et øvebord spiller du alene mod tre bots i hjerterfri.
      </p>
    </>
  )
}
