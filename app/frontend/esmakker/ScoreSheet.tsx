import type { SeatIndex } from "~/table/messages"
import type { EsmakkerPoints, ScoreRow } from "./messages"
import { LOOKUP_COLUMNS, lookupCell, lookupNotes, lookupTable, sheetRows, signedPoints, standing, totalPoints } from "./score"

/**
 * The es-makker score sheet ("stillingsark"): every runde's melding,
 * melder, esmakker, trump, stik and gik hjem / bet, the points per seat
 * and the running totals, as the server sent them. It replaces the paper
 * table; the lookup table under it is the family's reference card.
 */
export function EsmakkerScoreSheet(props: { results: ScoreRow[]; names: string[]; totals: number[]; leaders: SeatIndex[]; me: SeatIndex }) {
  const { results, names, totals, leaders, me } = props
  const rows = sheetRows(results, names)
  const seatClass = (seat: number) => [seat === me ? "is-me" : "", leaders.includes(seat as SeatIndex) ? "is-leader" : ""].filter(Boolean).join(" ") || undefined
  return (
    <div className="esmakker-sheet table-score-scroll">
      <table className="table-score">
        <thead>
          <tr>
            <th scope="col">#</th>
            <th scope="col">Melding</th>
            <th scope="col">Melder</th>
            <th scope="col">Makker</th>
            <th scope="col">Trumf</th>
            <th scope="col">Stik</th>
            <th scope="col">Resultat</th>
            {names.map((name, seat) => (
              <th key={seat} scope="col" className={seatClass(seat)}>
                {name}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && (
            <tr>
              <td colSpan={7 + names.length} className="esmakker-sheet-empty">
                Ingen runder endnu. Alle starter på 0 point.
              </td>
            </tr>
          )}
          {rows.map((row) => (
            <tr key={row.number}>
              <td>{row.number}</td>
              <th scope="row">{row.melding}</th>
              <td>{row.melder}</td>
              <td>{row.makker}</td>
              <td>{row.trump}</td>
              <td>{row.stik}</td>
              <td className={row.outcome === "Hjem" ? "is-home" : row.outcome === "Bet" ? "is-bet" : undefined}>{row.outcome}</td>
              {names.map((_, seat) => (
                <td key={seat} className={seatClass(seat)}>
                  <span className="esmakker-sheet-points">{signedPoints(row.points[seat] ?? 0)}</span>
                  <small>{totalPoints(row.totals[seat] ?? 0)}</small>
                </td>
              ))}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <th scope="row" colSpan={7}>
              I alt
            </th>
            {names.map((_, seat) => (
              <td key={seat} className={seatClass(seat)}>
                {totalPoints(totals[seat] ?? 0)}
              </td>
            ))}
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

/** The final standing: highest total first. */
export function EsmakkerStanding({ totals, names, me }: { totals: number[]; names: string[]; me: SeatIndex }) {
  return (
    <ol className="esmakker-standing">
      {standing(totals, names).map((line) => (
        <li key={line.seat} className={[line.place === 1 ? "is-first" : "", line.seat === me ? "is-me" : ""].filter(Boolean).join(" ") || undefined}>
          <span className="esmakker-standing-place">{line.place}.</span>
          <span>{line.seat === me ? `${line.name} (dig)` : line.name}</span>
          <strong>{totalPoints(line.total)}</strong>
        </li>
      ))}
    </ol>
  )
}

/** REGLER's lookup table (melding × præcis, +1 … +5) from the bord's point values, with its notes. */
export function EsmakkerLookupTable({ points }: { points: EsmakkerPoints }) {
  return (
    <section className="esmakker-lookup" aria-labelledby="esmakker-lookup-title">
      <h3 id="esmakker-lookup-title">Opslagstabel</h3>
      <p>Gevinst pr. taber og vinder, når meldingen går hjem.</p>
      <div className="table-score-scroll">
        <table className="table-score">
          <thead>
            <tr>
              <th scope="col">Melding</th>
              {LOOKUP_COLUMNS.map((column) => (
                <th key={column} scope="col">
                  {column}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {lookupTable(points).map((row) => (
              <tr key={row.label} className={`is-${row.kind}`}>
                <th scope="row">{row.label}</th>
                {row.cells.map((cell, index) => (
                  <td key={index}>{lookupCell(cell)}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul>
        {lookupNotes(points).map((note) => (
          <li key={note}>{note}</li>
        ))}
      </ul>
    </section>
  )
}

/** The score sheet and the lookup table as a modal: on a narrow screen, where the panel has no tabs. */
export function EsmakkerScoreModal(props: { results: ScoreRow[]; names: string[]; totals: number[]; leaders: SeatIndex[]; me: SeatIndex; points: EsmakkerPoints; onClose: () => void }) {
  const { onClose, points, ...sheet } = props
  return (
    <div className="table-modal" role="dialog" aria-modal="true" aria-labelledby="esmakker-score-title" onClick={onClose}>
      <div className="table-modal-panel esmakker-panel-score" onClick={(event) => event.stopPropagation()}>
        <header className="table-modal-header">
          <h2 id="esmakker-score-title">Stilling</h2>
          <button type="button" onClick={onClose}>
            Luk
          </button>
        </header>
        <p className="table-modal-note">Point vindes og tabes mellem spillerne; summen er altid 0. Højeste total vinder.</p>
        <EsmakkerScoreSheet {...sheet} />
        <EsmakkerLookupTable points={points} />
      </div>
    </div>
  )
}
