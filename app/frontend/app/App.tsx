import { Lobby } from "~/lobby/Lobby"
import { TablePage } from "~/table/TablePage"

/** Which page to show comes from the server-rendered mount point's data attributes. */
export function App({ dataset }: { dataset: DOMStringMap }) {
  if (dataset.page === "table" && dataset.tableId) return <TablePage tableId={Number(dataset.tableId)} />

  return <Lobby practiceTablesPath={dataset.practiceTablesPath ?? "/practice_tables"} />
}
