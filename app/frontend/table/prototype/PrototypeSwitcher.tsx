// PROTOTYPE (throwaway): floating bar that cycles ?variant= on the current page.
// Only rendered in dev builds; see TablePage.
import { useEffect } from "react"

export function PrototypeSwitcher({ variants, current }: { variants: { key: string; name: string }[]; current: string }) {
  const index = Math.max(
    0,
    variants.findIndex((variant) => variant.key === current),
  )
  const go = (step: number) => {
    const next = variants[(index + step + variants.length) % variants.length]
    if (!next) return
    const url = new URL(window.location.href)
    url.searchParams.set("variant", next.key)
    window.location.assign(url.toString())
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target?.closest("input, textarea, [contenteditable]")) return
      if (event.key === "ArrowLeft") go(-1)
      if (event.key === "ArrowRight") go(1)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  })

  const variant = variants[index]
  return (
    <div className="proto-switcher" role="navigation" aria-label="Prototype-varianter">
      <button type="button" onClick={() => go(-1)} aria-label="Forrige variant">
        ←
      </button>
      <span>
        {variant?.key} · {variant?.name}
      </span>
      <button type="button" onClick={() => go(1)} aria-label="Næste variant">
        →
      </button>
    </div>
  )
}
