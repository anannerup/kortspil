module Esmakker
  # The bank window's time ran out (REGLER §2.0; the window opens once the
  # vip melder has laid away, Anders 26 October 2026, and starts again
  # after the first bank). Nobody chooses it: the bord applies it, for the melder's
  # seat, when its timer fires (Table#close_bank_window). Logged so a
  # replay knows where the window closed.
  class CloseBankWindow < Data.define
    def to_h = {}
  end
end
