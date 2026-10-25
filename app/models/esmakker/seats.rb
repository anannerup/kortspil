module Esmakker
  # Who deals and who is forhånd (REGLER §2.0 "Kortgiver og forhånd"): the
  # forhånd is the seat after the kortgiver, and the kortgiver moves one
  # seat clockwise each runde. Seats are 0–3 clockwise.
  module Seats
    ALL = (0...SEAT_COUNT).to_a.freeze
    # The kortgiver of runde 1. Fixed for now: the vært sits in seat 0 and
    # deals first (an open question whether the deal should be drawn).
    FIRST_DEALER = 0

    module_function

    # The seat after `seat`, clockwise.
    def after(seat) = (seat + 1) % SEAT_COUNT

    def forhand(dealer) = after(dealer)
    def next_dealer(dealer) = after(dealer)
  end
end
