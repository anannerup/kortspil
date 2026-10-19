module Hjerterfri
  # The rules config a spil is played with. "Standard hjerterfri" follows
  # docs/rules Part 3 with both house-rule toggles (§3.9) off.
  #
  # - end_score: the spil ends when a seat reaches it after a runde (§3.7).
  # - queen_breaks_hearts: playing Q♠ breaks hearts, like a heart does.
  # - jack_of_diamonds_minus_ten: whoever takes J♦ scores −10 for the runde.
  #
  # Stored as a plain hash (#to_h / .from_h), e.g. in a JSON column.
  class Rules < Data.define(:end_score, :queen_breaks_hearts, :jack_of_diamonds_minus_ten)
    def self.standard = new

    # Accepts symbol or string keys; missing keys take the standard value.
    # Raises ArgumentError on unknown keys or invalid values.
    def self.from_h(hash) = new(**hash.to_h.transform_keys(&:to_sym))

    def initialize(end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false)
      raise ArgumentError, "end_score must be a positive integer" unless end_score.is_a?(Integer) && end_score.positive?
      unless [ queen_breaks_hearts, jack_of_diamonds_minus_ten ].all? { |toggle| [ true, false ].include?(toggle) }
        raise ArgumentError, "rule toggles must be true or false"
      end

      super
    end
  end
end
