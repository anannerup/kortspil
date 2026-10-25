# 08: Bank i bordet

**What to build:** Only at vip, within the bank window after trump is named (bord setting, default 8 s, shown as a countdown): the first bank must come from a seat that isn't the melder (the esmakker too if the bord allows it, default yes); after a bank only the melder can bank once more; at most two banks per runde; each bank doubles. The bank option looks the same to all non-melders so the hidden esmakker isn't revealed. The window is timed through the injectable scheduling seam.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Bank rules exactly as REGLER §2.0, incl. the esmakker setting.
- [ ] Countdown; window closes and play starts.
- [ ] Each bank ×2 in scoring (gevinst and bet).
- [ ] The UI doesn't reveal the esmakker.
- [ ] Table tests with fake scheduler/clock.
