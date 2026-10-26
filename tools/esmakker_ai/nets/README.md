# Nets

Start points for new training runs (`train start --init nets/FILE`), small
enough for git (~5 MB each). Checkpoints and the rest of a run stay outside
git (`runs/`).

- `mac2-step400k.pt`: the Mac run `mac2` at step 400 000 (26 October 2026),
  FORMAT 2. Rating +307, +0.59 ± 0.44 point/runde against Svær, +0.62 against
  PassBot (800 runder each). A FORMAT 3 run starts from it with the new
  spil inputs at zero, so it first plays exactly as this net.
