module Hjerterfri
  # The rules config a spil is played with. "Standard hjerterfri" follows
  # docs/rules Part 3 with every house rule (§3.9) off.
  #
  # - end_score: the spil ends when a seat reaches it after a runde (§3.7).
  # - queen_breaks_hearts: playing Q♠ breaks hearts, like a heart does.
  # - jack_of_diamonds_minus_ten: whoever takes J♦ scores −10 for the runde,
  #   unless they shot the moon.
  # - shooters_choice: a moon shooter chooses between 26 to everyone else
  #   and −26 to themselves. Off, everyone else always gets 26 (§3.6).
  #
  # Stored as a plain hash (#to_h / .from_h), e.g. in a JSON column.
  class Rules < Data.define(:end_score, :queen_breaks_hearts, :jack_of_diamonds_minus_ten, :shooters_choice)
    TOGGLES = %i[queen_breaks_hearts jack_of_diamonds_minus_ten shooters_choice].freeze

    # Why an action refuses a rules form this class cannot read.
    INVALID = :invalid_end_score

    def self.standard = new

    # The fields of the rules form (strong parameters).
    def self.form_fields = [ :end_score, *TOGGLES ]

    # The rules from the rules form (string values; unticked toggles are
    # off), or nil when the end score is not a positive whole number.
    def self.from_form(form)
      end_score = Integer(form[:end_score].to_s, exception: false)
      return nil unless end_score&.positive?

      new(end_score:, **TOGGLES.index_with { |toggle| form[toggle] == "1" })
    end

    # Accepts symbol or string keys; missing keys take the standard value.
    # Raises ArgumentError on unknown keys or invalid values.
    def self.from_h(hash) = new(**hash.to_h.transform_keys(&:to_sym))

    # For stored snapshots: keys this version does not know are dropped, so
    # older rows keep loading when toggles are added or removed.
    def self.from_stored(hash) = from_h(hash.to_h.transform_keys(&:to_sym).slice(*members))

    def initialize(end_score: 100, queen_breaks_hearts: false, jack_of_diamonds_minus_ten: false, shooters_choice: false)
      raise ArgumentError, "end_score must be a positive integer" unless end_score.is_a?(Integer) && end_score.positive?
      unless [ queen_breaks_hearts, jack_of_diamonds_minus_ten, shooters_choice ].all? { |toggle| [ true, false ].include?(toggle) }
        raise ArgumentError, "rule toggles must be true or false"
      end

      super
    end
  end
end
