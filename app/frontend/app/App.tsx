import { Lobby } from "~/lobby/Lobby"
import type { Rules } from "~/table/messages"
import { TablePage } from "~/table/TablePage"

/** Which page to show comes from the server-rendered mount point's data attributes. */
export function App({ dataset }: { dataset: DOMStringMap }) {
  if (dataset.page === "table" && dataset.tableId) {
    const tableId = Number(dataset.tableId)
    return <TablePage tableId={tableId} departurePath={dataset.departurePath ?? `/tables/${tableId}/departure`} />
  }

  return (
    <Lobby
      practiceTablesPath={dataset.practiceTablesPath ?? "/practice_tables"}
      standardRules={JSON.parse(dataset.standardRules ?? "{}") as Rules}
    />
  )
}
