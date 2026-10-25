# Es-makker whist (docs/rules/REGLER.da.md §2, with §2.0 "Vores bord"
# winning where they differ): the plain-Ruby rules engine, next to
# Hjerterfri. No ActiveRecord, no IO; randomness is injected (`shuffler:`).
#
# Built so far (ticket 01): the 55-card deck (Card), the deal with the
# kitty (Deal), who deals and who is forhånd (Seats), a runde (Round) with
# what each seat may see and its append-only action log, the spil (Game)
# and the bord's rules (Rules, Points). The meldingsrunde and everything
# after it come in later tickets as intents on Round.
module Esmakker
  SEAT_COUNT = 4
end
