import type { LobbyTable } from "./messages"

/** A padlock, inline SVG in the text colour. */
export function LockIcon() {
  return (
    <svg className="lobby-lock" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M8 1a3.5 3.5 0 0 0-3.5 3.5V6H4a1.5 1.5 0 0 0-1.5 1.5v6A1.5 1.5 0 0 0 4 15h8a1.5 1.5 0 0 0 1.5-1.5v-6A1.5 1.5 0 0 0 12 6h-.5V4.5A3.5 3.5 0 0 0 8 1Zm2 5H6V4.5a2 2 0 1 1 4 0V6Z"
      />
    </svg>
  )
}

/** The table type as a pill: a lock for a password table, "Privat" for a private one, "Øvebord"; nothing for an open table. */
export function TableKindPill({ kind }: { kind: LobbyTable["kind"] }) {
  if (kind === "password")
    return (
      <span className="pill pill-amber">
        <LockIcon /> Adgangskode
      </span>
    )
  if (kind === "private") return <span className="pill pill-blue">Privat</span>
  if (kind === "practice") return <span className="pill pill-blue">Øvebord</span>
  return null
}
