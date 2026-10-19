# 01: Skeleton with React

**What to build:** The fresh Rails app serves a React + TypeScript page built with Vite, running locally with one command. The Kamal config targets kortspil.andersnannerup.dk on the same VPS as the training app, so the first deploy is only a matter of secrets and DNS. CI runs the test suite.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [x] Visiting the root URL locally shows a React-rendered page (TypeScript, strict mode)
- [x] `bin/dev` starts Rails and Vite together
- [x] The Kamal config mirrors `../training`: service `kortspil`, image `anannerup/kortspil`, volume `kortspil_storage`, amd64, `ssh.user: ubuntu`, proxy with SSL for kortspil.andersnannerup.dk
- [x] The production Docker image builds the Vite assets
- [x] CI runs `bin/rails test` and the TypeScript type check
- [ ] The initial state is committed to git
