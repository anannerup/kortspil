module Hjerterfri
  # The intent to pass three cards, given by their codes (%w[QS AH KH]).
  class Pass < Data.define(:cards)
  end
end
