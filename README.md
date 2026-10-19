# Kortspil

Multiplayer card games at kortspil.andersnannerup.dk. See `CLAUDE.md` and
`PLAN.md` for the stack and decisions.

Run the test suite with `bin/rails test`.

## Granting admin rights

Admin rights can only be granted from the Rails console; there is no way to
set or remove the admin flag in the UI. In production:

```sh
bin/kamal console
```

```ruby
User.find_by(username: "...").update!(admin: true, approval_state: :approved)
```

To remove admin rights again, run the same with `admin: false`. Admins then see
an "Admin" link in the top bar, leading to `/admin`.
