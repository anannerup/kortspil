/** The lobby placeholder: for now only the practice table. */
export function Lobby({ practiceTablesPath }: { practiceTablesPath: string }) {
  const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""

  return (
    <main>
      <h1>Kortspil</h1>
      <form method="post" action={practiceTablesPath}>
        <input type="hidden" name="authenticity_token" value={csrfToken} />
        <button type="submit">Øvebord</button>
      </form>
      <p>Spil en runde hjerterfri mod tre bots.</p>
    </main>
  )
}
