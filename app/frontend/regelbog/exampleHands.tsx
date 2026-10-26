import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { CardFace } from "~/cards"

/**
 * The regelbog's example hands: the server renders each as the cards in
 * words with their codes in data-card-hand (RegelbogHelper#example_hand);
 * here they are drawn with the site's own cards.
 */
export function mountExampleHands(root: ParentNode = document) {
  root.querySelectorAll<HTMLElement>("[data-card-hand]").forEach((element) => {
    const codes = (element.dataset.cardHand ?? "").split(/\s+/).filter(Boolean)
    createRoot(element).render(
      <StrictMode>
        {codes.map((code, index) => (
          <CardFace key={`${code}-${index}`} code={code} size="sm" />
        ))}
      </StrictMode>,
    )
  })
}
