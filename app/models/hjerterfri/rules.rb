module Hjerterfri
  # The rules config a spil is played with. "Standard hjerterfri" follows
  # docs/rules Part 3. House-rule toggles (Q♠ breaks hearts, J♦ −10) are
  # added here when they are built.
  class Rules < Data.define(:end_score)
    def self.standard = new(end_score: 100)
  end
end
