# 03: Signup, login and approval gate

**What to build:** A visitor creates an account with username, email and password and is logged in. An unapproved user sees only an "Afventer godkendelse" page. An approved user reaches the (empty) lobby. A blocked user is refused at login. Users can change their own password.

**Blocked by:** 01 (Skeleton with React)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] The account system is built on the Rails 8 authentication generator. Usernames and emails are unique (case-insensitive).
- [x] Login accepts either username or email, plus the password
- [x] Approval states: pending (the default), approved, rejected, blocked
- [x] Pending and rejected users see only the waiting page. Blocked users can't log in and get a plain message.
- [x] Signed-in users can change their own password. There is no email-based reset.
- [x] There is an admin flag. It is not exposed in any form.
- [x] Request tests cover signup, login by username, login by email, the pending gate, the blocked refusal and the password change

## Comments

- Deployed 2026-10-20. Admin user `anders` created in prod; tested by Anders.
