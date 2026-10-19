# 02: First deploy

**What to build:** The skeleton is live over HTTPS at kortspil.andersnannerup.dk. This needs Anders: Cloudflare DNS, a Docker Hub repo, secrets, and Docker running locally.

**Blocked by:** 01 (Skeleton with React)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] Cloudflare A record `kortspil → 141.95.53.184` is DNS-only (grey cloud)
- [x] The `anannerup/kortspil` repo exists on Docker Hub (or GHCR is used if the free private-repo limit gets in the way)
- [x] `.kamal/secrets` holds `RAILS_MASTER_KEY` and the registry password, which is read from the environment as in training
- [x] `kamal deploy` succeeds, and https://kortspil.andersnannerup.dk shows the React page with a valid certificate
- [x] training.andersnannerup.dk still works

## Comments

- 2026-10-20: live at https://kortspil.andersnannerup.dk with a Let's Encrypt cert. Training unaffected. Fixed a missing `npx` in the Dockerfile on the way. Deploy with `bin/kamal deploy` from main.
