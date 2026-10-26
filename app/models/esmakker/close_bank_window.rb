module Esmakker
  # The bank window's time ran out (REGLER §2.0: "5–10 sekunder efter trumf
  # er meldt"). Nobody chooses it: the bord applies it, for the melder's
  # seat, when its timer fires (Table#close_bank_window). Logged so a
  # replay knows where the window closed.
  class CloseBankWindow < Data.define
    def to_h = {}
  end
end
