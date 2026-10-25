module Esmakker
  # The melder calls an ace by its suit ("C", "D", "H", "S"): whoever
  # holds it is the esmakker. A suit that is none is rejected.
  class CallAce < Data.define(:suit)
    def to_h = { suit: }
  end
end
