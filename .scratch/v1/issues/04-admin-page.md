# 04: Admin page

**What to build:** The admin sees users awaiting approval and can approve or reject them. They also see all users and can block a user or set a new password. Non-admins can't reach any of it.

**Blocked by:** 03 (Signup, login and approval gate)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] The pending list offers approve and reject
- [x] The all-users list shows each user's status and offers block, unblock and set new password
- [x] Admin rights can only be granted from the Rails console. This is documented in the README.
- [x] Non-admins get 404 or a redirect on every admin route
- [x] Request tests cover each admin action and the non-admin denial

## Comments

- Deployed 2026-10-20 and tested by Anders. `users:create_admin` rake task added alongside.
