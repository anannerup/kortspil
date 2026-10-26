import type { MoonChoiceOption, Rules, Score, SeatIndex, SeatInfo, SeatView, HjerterfriTableState } from "./messages"
import { BOT_LEVEL_NAMES, DIRECTION_LABELS, joinNames, pointsLabel, rulesSummary, seatLabel } from "./texts"

/** "Stilling": one row per completed runde, one column per player, totals and the leader. */
export function ScoreSheet(props: { seats: SeatInfo[]; score: Score; rules: Rules; onClose: () => void }) {
  const { seats, score, rules, onClose } = props
  return (
    <div className="table-modal" role="dialog" aria-modal="true" aria-labelledby="score-title" onClick={onClose}>
      <div className="table-modal-panel" onClick={(event) => event.stopPropagation()}>
        <header className="table-modal-header">
          <h2 id="score-title">Stilling</h2>
          <button type="button" onClick={onClose}>
            Luk
          </button>
        </header>
        <p className="table-modal-note">Spillet slutter, når en spiller når {score.end_score} point. Laveste total vinder.</p>
        <p className="table-modal-note">Regler: {rulesSummary(rules)}</p>
        <ScoreTable seats={seats} score={score} />
      </div>
    </div>
  )
}

export function ScoreTable({ seats, score }: { seats: SeatInfo[]; score: Score }) {
  const marked = score.winners.length > 0 ? score.winners : score.leaders
  const mark = score.winners.length > 0 ? "vinder" : "fører"
  const isMarked = (seat: SeatIndex) => marked.includes(seat)
  return (
    <div className="table-score-scroll">
      <table className="table-score">
        <thead>
          <tr>
            <th scope="col">Runde</th>
            <th scope="col">Bytte</th>
            {seats.map((seat) => (
              <th key={seat.seat} scope="col" className={isMarked(seat.seat) ? "is-leader" : undefined}>
                <ScoreName seat={seat} />
                {isMarked(seat.seat) && <span className="table-leader-mark"> ({mark})</span>}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {score.rows.length === 0 && (
            <tr>
              <td colSpan={2 + seats.length}>Ingen runder er spillet endnu.</td>
            </tr>
          )}
          {score.rows.map((row) => (
            <tr key={row.number}>
              <th scope="row">{row.number}</th>
              <td>{DIRECTION_LABELS[row.pass_direction]}</td>
              {seats.map((seat) => (
                <td key={seat.seat}>{row.points[seat.seat] ?? 0}</td>
              ))}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <th scope="row" colSpan={2}>
              I alt
            </th>
            {seats.map((seat) => (
              <td key={seat.seat} className={isMarked(seat.seat) ? "is-leader" : undefined}>
                {score.totals[seat.seat] ?? 0}
              </td>
            ))}
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

/** A column's player; a bot's level on a line of its own, so the columns stay narrow. */
function ScoreName({ seat }: { seat: SeatInfo }) {
  if (!seat.bot || !seat.bot_level || seat.took_over_from) return <>{seatLabel(seat)}</>
  return (
    <>
      {seat.name}
      <small className="table-score-level">{BOT_LEVEL_NAMES[seat.bot_level]}</small>
    </>
  )
}

/** The points of the runde just played, shown until the next runde is dealt. */
export function RundeResult({ state, onNext }: { state: HjerterfriTableState; onNext: () => void }) {
  const { seats, view, points_taken: taken, score } = state
  return (
    <div className="table-overlay" role="dialog" aria-labelledby="runde-result-title">
      <h2 id="runde-result-title">Runde {state.round_number} er slut</h2>
      <MoonNote seats={seats} view={view} />
      <JackNote seats={seats} view={view} rules={state.rules} />
      <table className="table-score">
        <thead>
          <tr>
            <th scope="col">Spiller</th>
            <th scope="col">Taget</th>
            <th scope="col">Point i runden</th>
            <th scope="col">I alt</th>
          </tr>
        </thead>
        <tbody>
          {seats.map((seat) => (
            <tr key={seat.seat}>
              <th scope="row">{seatLabel(seat)}</th>
              <td>{taken[seat.seat] ?? 0}</td>
              <td>
                <strong>{view.points[seat.seat] ?? 0}</strong>
              </td>
              <td>{score.totals[seat.seat] ?? 0}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="table-overlay-note">Næste runde starter om lidt.</p>
      <button type="button" onClick={onNext}>
        Næste runde
      </button>
    </div>
  )
}

/**
 * The end screen: the vindere (ties share; never a bot) and final totals.
 * Everyone at the bord now waits for the next spil at a new bord in the
 * lobby (`next_path`): go there to play again, or stand up.
 */
export function GameOver(props: { state: HjerterfriTableState; onNext: () => void; onLeave: () => void }) {
  const { state, onNext, onLeave } = props
  const { seats, score, view } = state
  const winners = score.winners.map((seat) => seats[seat]?.name ?? "")
  const me = view.seat
  // A bot never wins: with a bot alone on the lowest total there is no vinder.
  const headline =
    winners.length === 0
      ? "Ingen vinder — en bot fik færrest point"
      : winners.length > 1
        ? `Delt sejr: ${joinNames(winners)}`
        : score.winners[0] === me
          ? "Du vandt!"
          : `${winners[0] ?? ""} vandt`
  return (
    <div className="table-overlay" role="dialog" aria-labelledby="game-over-title">
      <h2 id="game-over-title">Spillet er slut · {headline}</h2>
      <MoonNote seats={seats} view={view} />
      <JackNote seats={seats} view={view} rules={state.rules} />
      <p className="table-overlay-note">
        Sidste runde:{" "}
        {seats.map((seat) => `${seat.name} ${pointsLabel(view.points[seat.seat] ?? 0)}`).join(" · ")}
      </p>
      <ScoreTable seats={seats} score={score} />
      <p className="table-overlay-note">I sidder nu ved et nyt bord i lobbyen. Bliv siddende for at spille igen, eller rejs dig.</p>
      <div className="table-overlay-buttons">
        <button type="button" onClick={onNext} disabled={!state.next_path}>
          Til bordet
        </button>
        <button type="button" onClick={onLeave}>
          Forlad bordet
        </button>
      </div>
    </div>
  )
}

/** What the moon gave, as the server scored it (moon_choice when the shooter chose). */
const MOON_OUTCOMES: Record<MoonChoiceOption, (name: string) => string> = {
  add_to_others: (name) => `0 point til ${name}, 26 til de andre`,
  subtract_from_self: (name) => `−26 til ${name}, 0 til de andre`,
}

function MoonNote({ seats, view }: { seats: SeatInfo[]; view: SeatView }) {
  const shooter = view.moon_shooter
  if (shooter === null) return <p className="table-overlay-note">&nbsp;</p>
  const name = seats[shooter]?.name ?? ""
  return (
    <p className="table-overlay-note table-moon">
      {name} tog alle 26 point og skød månen: {MOON_OUTCOMES[view.moon_choice ?? "add_to_others"](name)}.
    </p>
  )
}

/** Who took J♦, when the table plays "ruder knægt giver minus 10". */
function JackNote({ seats, view, rules }: { seats: SeatInfo[]; view: SeatView; rules: Rules }) {
  const taker: SeatIndex | null = view.jack_of_diamonds_taker
  if (!rules.jack_of_diamonds_minus_ten || taker === null) return null
  const name = seats[taker]?.name ?? ""
  const counted = taker !== view.moon_shooter
  return (
    <p className="table-overlay-note">
      {name} tog ruder knægt{counted ? ": −10." : ", men den tæller ikke, når man skyder månen."}
    </p>
  )
}

/** Shown while the moon shooter chooses (shooter's choice): buttons for the shooter, a wait for the rest. */
export function MoonChoice(props: { state: HjerterfriTableState; onChoose: (option: MoonChoiceOption) => void }) {
  const { state, onChoose } = props
  const { view, seats } = state
  const shooter = view.moon_shooter
  const name = shooter === null ? "" : (seats[shooter]?.name ?? "")
  return (
    <div className="table-overlay" role="dialog" aria-labelledby="moon-choice-title">
      <h2 id="moon-choice-title">{view.to_act === view.seat ? "Du skød månen!" : `${name} skød månen`}</h2>
      {view.to_act === view.seat ? (
        <div className="table-overlay-buttons">
          <button type="button" onClick={() => onChoose("add_to_others")}>
            26 til de andre
          </button>
          <button type="button" onClick={() => onChoose("subtract_from_self")}>
            −26 til mig
          </button>
        </div>
      ) : (
        <p className="table-overlay-note">{name} vælger 26 til de andre eller −26 til sig selv…</p>
      )}
    </div>
  )
}
