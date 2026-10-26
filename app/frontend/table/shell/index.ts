// The table shell: what is the same at every game's bord, and only that
// (.scratch/table-refactor/issues/04-table-shell.md). The subscription and
// its message routing, the panel's frame, the toasts, the leave form, the
// opponents' stacks and the hooks for measuring the felt. The hands, the
// timelines, the centre of the felt, the tab bodies, the score sheets and
// the status text are each game's own.
export { useAnchors, useHandSize, useMediaQuery, useTrickAnchors } from "./hooks"
export { LeaveForm, OpponentStack, TableToasts } from "./Felt"
export { TablePanel } from "./TablePanel"
export { useTableShell, type ShellState, type Send, type TableShell } from "./useTableShell"
