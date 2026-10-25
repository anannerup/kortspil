import type { LobbyTable } from "./messages"
import { csrfToken } from "./PostForm"

/** The answer to a table action: the bord as it is now, or why the bord refused (in Danish). */
export type TableActionResult = { table: LobbyTable } | { error: string }

/**
 * Sends one of the bord's pre-game actions (sit, bot, kick, settings,
 * start) from its table page, the same request a form would send, and
 * gets the bord back as JSON (ApplicationController#render_outcome), so the page updates
 * without a reload. Everyone else at the bord hears of it on LobbyChannel.
 */
export async function sendTableAction(path: string, fields: Record<string, string>, method: "post" | "patch" | "delete" = "post"): Promise<TableActionResult> {
  const body = new FormData()
  if (method !== "post") body.append("_method", method)
  for (const [name, value] of Object.entries(fields)) body.append(name, value)
  try {
    const response = await fetch(path, {
      method: "POST",
      body,
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
    })
    const answer = (await response.json()) as Partial<{ table: LobbyTable; error: string }>
    if (response.ok && answer.table) return { table: answer.table }
    return { error: answer.error ?? "Det gik ikke. Prøv igen." }
  } catch {
    return { error: "Ingen forbindelse. Prøv igen." }
  }
}
