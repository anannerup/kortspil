module Esmakker
  class Bidding
    # The intent to bid a melding (an Esmakker::Melding; nil for a code that
    # is no melding, which the bidding rejects).
    class Bid < Data.define(:melding)
      # The melding as its code, e.g. for a rejection sent to the client.
      def to_h = { melding: melding&.to_s }
    end
  end
end
