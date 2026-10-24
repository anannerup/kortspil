import { Lobby } from "~/lobby/Lobby"
import type { LobbyTable } from "~/lobby/messages"
import { WaitingRoom } from "~/lobby/WaitingRoom"
import type { Rules } from "~/table/messages"
import { TablePage } from "~/table/TablePage"

/** Which page to show comes from the server-rendered mount point's data attributes. */
export function App({ dataset }: { dataset: DOMStringMap }) {
  if (dataset.page === "table" && dataset.tableId) {
    const tableId = Number(dataset.tableId)
    return <TablePage tableId={tableId} departurePath={dataset.departurePath ?? `/tables/${tableId}/departure`} />
  }
  if (dataset.page === "waiting" && dataset.table) {
    return <WaitingRoom initialTable={JSON.parse(dataset.table) as LobbyTable} userId={Number(dataset.userId)} />
  }

  return (
    <Lobby
      practiceTablesPath={dataset.practiceTablesPath ?? "/practice_tables"}
      tablesPath={dataset.tablesPath ?? "/tables"}
      standardRules={JSON.parse(dataset.standardRules ?? "{}") as Rules}
      initialTables={JSON.parse(dataset.tables ?? "[]") as LobbyTable[]}
      userId={Number(dataset.userId)}
      currentTablePath={dataset.currentTablePath ?? null}
    />
  )
}
