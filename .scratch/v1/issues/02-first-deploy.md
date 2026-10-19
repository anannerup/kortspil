# 02: First deploy

**What to build:** The skeleton is live over HTTPS at kortspil.andersnannerup.dk. This needs Anders: Cloudflare DNS, a Docker Hub repo, secrets, and Docker running locally.

**Blocked by:** 01 (Skeleton with React)

**Status:** ready-for-human

Spec: `.scratch/v1/spec.md`

- [ ] Cloudflare A record `kortspil → 141.95.53.184` is DNS-only (grey cloud)
- [ ] The `anannerup/kortspil` repo exists on Docker Hub (or GHCR is used if the free private-repo limit gets in the way)
- [ ] `.kamal/secrets` holds `RAILS_MASTER_KEY` and the registry password, which is read from the environment as in training
- [ ] `kamal deploy` succeeds, and https://kortspil.andersnannerup.dk shows the React page with a valid certificate
- [ ] training.andersnannerup.dk still works
