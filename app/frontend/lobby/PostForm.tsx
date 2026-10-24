import type { FormEvent, ReactNode } from "react"

/**
 * A plain POST form with the CSRF token; the server answers with a
 * redirect. `method` "patch" or "delete" is sent as Rails' `_method`.
 * `confirm` asks before submitting.
 */
export function PostForm(props: {
  action: string
  id?: string
  className?: string
  method?: "patch" | "delete"
  confirm?: string
  onSubmit?: () => void
  children?: ReactNode
}) {
  const { action, id, className, method, confirm, onSubmit, children } = props
  const submit = (event: FormEvent<HTMLFormElement>) => {
    if (confirm && !window.confirm(confirm)) {
      event.preventDefault()
      return
    }
    onSubmit?.()
  }

  return (
    <form method="post" action={action} id={id} className={className} onSubmit={submit}>
      <input type="hidden" name="authenticity_token" value={csrfToken()} />
      {method && <input type="hidden" name="_method" value={method} />}
      {children}
    </form>
  )
}

export function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}
