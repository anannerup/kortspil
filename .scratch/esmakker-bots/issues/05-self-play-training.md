# 05: Selvspil-træning

**What to build:** Self-play training in PyTorch (DouZero-style: a net scores each legal action; heads for expected stik per seat and runde points) that runs on Anders's Windows PC (RTX 3070, CUDA): one command to start, one to stop, checkpoints at fixed intervals, resumes where it stopped. A share of games (start 25 %) seat Svær as the other players. Setup guide for Windows. Measurement: same-hand duplicate against the first bot and Svær.

**Blocked by:** 04, and 03 for the Svær partners

**Status:** ready-for-agent

- [ ] Start, stop, resume work; checkpoints not in git.
- [ ] Training beats the first bot measurably.
