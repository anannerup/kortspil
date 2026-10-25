# 16: Nudges (puf)

**What to build:** The host nudges friends to the table. The friend gets a live notification anywhere on the site and can accept (and is seated) or decline. Pending nudges + seated players + bots never exceed 4. Nudges expire after about 5 minutes or when the spil starts, and the host can withdraw them.

**Blocked by:** 13 (Host controls), 14 (Password and private tables), 15 (Friends)

**Status:** done

Spec: `.scratch/v1/spec.md`

- [x] Only friends can be nudged, and only by the host
- [x] The cap is enforced: pending + seated + bots ≤ 4. A decline, expiry or withdrawal frees the slot.
- [x] Accepting seats the friend in a free seat. This works for private and password tables without the password.
- [x] The host sees each nudge's state
- [x] Expiry is driven by the injected clock
- [x] Table-seam tests cover the cap, expiry, withdrawal, accept and decline

## Comments

2026-10-25: Built from the bord before its spil (TableSetup's "Inviter"
section, vært only). Pufs live on the waiting bord in memory
(docs/adr/0002-waiting-tables-in-memory.md), not in a table of their own
as the spec's Persistence section says: they only exist before a spil and
end with it. A pending puf holds a seat, so nobody else may take it and
the vært may not put a bot there; the spil can start once the friend has
answered or the puf is withdrawn or expired. The friend gets the puf in
the notification stack on any page ("Sæt mig ved bordet" / "Nej tak"),
again on page load while pending. Expiry is lazy: on the next change to
the bord, or when the bord's page asks at the expiry time. Tests:
test/models/nudges_test.rb, test/controllers/nudges_controller_test.rb.

2026-10-26 (Anders): a puf holds the seat for 60 seconds (was five
minutes), and every seated player may puf their own friends, not only the
vært. The puf remembers who sent it (`from_id`, `from_name`; the friend's
notification names them); the sender or the vært may withdraw it. The cap
is unchanged: seated + bots + pending pufs ≤ 4.
