import { Lobby } from "~/lobby/Lobby"
import type { LobbyTable } from "~/lobby/messages"
import { TablePage } from "~/table/TablePage"
import { TableSetup } from "~/table/TableSetup"

/** Which page to show comes from the server-rendered mount point's data attributes. */
export function App({ dataset }: { dataset: DOMStringMap }) {
  if (dataset.page === "table" && dataset.tableId) {
    const tableId = Number(dataset.tableId)
    return <TablePage tableId={tableId} departurePath={dataset.departurePath ?? `/tables/${tableId}/departure`} userId={Number(dataset.userId)} />
  }
  if (dataset.page === "waiting" && dataset.table) {
    const table = JSON.parse(dataset.table) as LobbyTable
    return (
      <TableSetup
        initialTable={table}
        userId={Number(dataset.userId)}
        departurePath={dataset.departurePath ?? `/tables/${table.id}/departure`}
        notice={dataset.notice ?? null}
      />
    )
  }

  return (
    <Lobby
      practiceTablesPath={dataset.practiceTablesPath ?? "/practice_tables"}
      tablesPath={dataset.tablesPath ?? "/tables"}
      initialTables={JSON.parse(dataset.tables ?? "[]") as LobbyTable[]}
      userId={Number(dataset.userId)}
      currentTablePath={dataset.currentTablePath ?? null}
    />
  )
}
