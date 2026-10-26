import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "~/app/App"
import { Notifications } from "~/notifications/Notifications"
import { startCountdowns } from "~/app/countdown"
import { mountExampleHands } from "~/regelbog/exampleHands"

const container = document.getElementById("root")

if (container) {
  createRoot(container).render(
    <StrictMode>
      <App dataset={container.dataset} />
    </StrictMode>,
  )
}

// On every page for signed-in players: presence and personal notifications.
const notifications = document.getElementById("notifications")
if (notifications) {
  createRoot(notifications).render(
    <StrictMode>
      <Notifications friendsPath={notifications.dataset.friendsPath ?? "/friendships"} />
    </StrictMode>,
  )
}
startCountdowns()
// The regelbog's example hands, drawn with the site's cards.
mountExampleHands()
