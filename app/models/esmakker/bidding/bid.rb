module Esmakker
  class Bidding
    # The intent to bid a melding (an Esmakker::Melding).
    class Bid < Data.define(:melding)
    end
  end
end
