import type { ReactNode } from "react"

/** A plain POST form with the CSRF token; the server answers with a redirect. */
export function PostForm({ action, className, children }: { action: string; className?: string; children: ReactNode }) {
  return (
    <form method="post" action={action} className={className}>
      <input type="hidden" name="authenticity_token" value={csrfToken()} />
      {children}
    </form>
  )
}

export function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}
