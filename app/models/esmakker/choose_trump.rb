module Esmakker
  # The melder names trump: a Trump, or nil for a code that is none (which
  # the runde rejects).
  class ChooseTrump < Data.define(:trump)
    # The trump as its code, e.g. for a rejection sent to the client.
    def to_h = { trump: trump&.to_s }
  end
end
