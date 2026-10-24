import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "~/app/App"
import { startCountdowns } from "~/app/countdown"

const container = document.getElementById("root")

if (container) {
  createRoot(container).render(
    <StrictMode>
      <App dataset={container.dataset} />
    </StrictMode>,
  )
}

startCountdowns()
