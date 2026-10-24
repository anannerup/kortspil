/**
 * Live countdowns in server-rendered pages: every element with
 * data-countdown="<seconds>" counts down to 0:00 as m:ss, from when the
 * page loaded. Used by the lobby banner for a spil waiting for you.
 */
export function startCountdowns(root: ParentNode = document): void {
  const elements = Array.from(root.querySelectorAll<HTMLElement>("[data-countdown]"))
  if (elements.length === 0) return
  const started = performance.now()
  const tick = () => {
    const elapsed = (performance.now() - started) / 1000
    for (const element of elements) {
      element.textContent = formatClock(Number(element.dataset.countdown) - elapsed)
    }
  }
  tick()
  setInterval(tick, 500)
}

/** Seconds as m:ss, never below 0:00. */
export function formatClock(seconds: number): string {
  const whole = Math.max(0, Math.ceil(seconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`
}
