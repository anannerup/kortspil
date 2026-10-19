# 16: Nudges (puf)

**What to build:** The host nudges friends to the table. The friend gets a live notification anywhere on the site and can accept (and is seated) or decline. Pending nudges + seated players + bots never exceed 4. Nudges expire after about 5 minutes or when the spil starts, and the host can withdraw them.

**Blocked by:** 13 (Host controls), 14 (Password and private tables), 15 (Friends)

**Status:** ready-for-agent

Spec: `.scratch/v1/spec.md`

- [ ] Only friends can be nudged, and only by the host
- [ ] The cap is enforced: pending + seated + bots ≤ 4. A decline, expiry or withdrawal frees the slot.
- [ ] Accepting seats the friend in a free seat. This works for private and password tables without the password.
- [ ] The host sees each nudge's state
- [ ] Expiry is driven by the injected clock
- [ ] Table-seam tests cover the cap, expiry, withdrawal, accept and decline
