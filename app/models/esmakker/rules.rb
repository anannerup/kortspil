module Esmakker
  # The card game's rules an es-makker bord plays by (its GameRules; the
  # number of runder is the bord's own, TableRules). Defaults are REGLER
  # §2.0 "Vores bord", every ⚙️ setting:
  #
  # - pahaeng_order: the påhæng tiers from highest to lowest on one number,
  #   strict (no two in one tier in v1). Standard vip > halve > gode.
  # - joker_trumpable: whether trump beats a joker. Standard no.
  # - esmakker_banks_first: whether the esmakker may make the first bank at
  #   vip. Standard yes (Anders, 25 October).
  # - bank_window: seconds the bank window stays open, 5–10. Standard 8.
  # - points: the point values (Points).
  #
  # Stored as a plain hash (#to_h / .from_h), e.g. in a JSON column.
  class Rules < Data.define(:pahaeng_order, :joker_trumpable, :esmakker_banks_first, :bank_window, :points)
    PAHAENG = %w[vip halve gode].freeze
    TOGGLES = %i[joker_trumpable esmakker_banks_first].freeze
    BANK_WINDOW = (5..10)
    # Why an action refuses a rules form this class cannot read.
    INVALID = :invalid_rules

    def self.standard = new

    # Accepts symbol or string keys; missing keys take the standard value.
    # Raises ArgumentError on unknown keys or invalid values.
    def self.from_h(hash)
      values = hash.to_h.transform_keys(&:to_sym)
      values[:points] = Points.from_h(values[:points]) if values.key?(:points) && !values[:points].is_a?(Points)
      new(**values)
    end

    # For stored snapshots: keys this version does not know are dropped, so
    # older rows keep loading when settings are added or removed.
    def self.from_stored(hash)
      values = hash.to_h.transform_keys(&:to_sym).slice(*members)
      values[:points] = Points.from_stored(values[:points]) if values.key?(:points)
      from_h(values)
    end

    # The fields of the settings form (strong parameters). The påhæng order
    # is one field, "vip,halve,gode".
    def self.form_fields
      [ *TOGGLES, :bank_window, :pahaeng_order, { points: [ *Points::FACTORS, *Points::AMOUNTS, { stakes: Points::NUMBERS } ] } ]
    end

    # The rules from the settings form (string values; unticked toggles are
    # off, a missing påhæng order or point keeps the standard), or nil when
    # a value is invalid. The påhæng order is "vip,halve,gode" (or a list).
    def self.from_form(form)
      order = form[:pahaeng_order]
      order = order.split(",") if order.is_a?(String)
      bank_window = Integer(form[:bank_window].to_s, exception: false)
      points = points_from_form(form[:points].to_h.transform_keys(&:to_sym))
      return nil unless points && bank_window

      new(pahaeng_order: order.presence || PAHAENG, bank_window:, points:, **TOGGLES.index_with { |toggle| form[toggle] == "1" })
    rescue ArgumentError
      nil
    end

    def self.points_from_form(form)
      stakes = form[:stakes].to_h.transform_keys(&:to_s).slice(*Points::NUMBERS).transform_values { |value| Points.amount(value) }
      amounts = form.slice(*Points::FACTORS, *Points::AMOUNTS).transform_values { |value| Points.amount(value) }
      return nil if stakes.values.any?(&:nil?) || amounts.values.any?(&:nil?)

      Points.from_h(stakes:, **amounts)
    end
    private_class_method :points_from_form

    def initialize(pahaeng_order: PAHAENG, joker_trumpable: false, esmakker_banks_first: true, bank_window: 8, points: Points.standard)
      order = pahaeng_order.map(&:to_s)
      raise ArgumentError, "the påhæng order holds #{PAHAENG.join(', ')} once each" unless order.sort == PAHAENG.sort
      raise ArgumentError, "rule toggles must be true or false" unless [ joker_trumpable, esmakker_banks_first ].all? { |toggle| [ true, false ].include?(toggle) }
      raise ArgumentError, "the bank window is #{BANK_WINDOW} seconds" unless bank_window.is_a?(Integer) && BANK_WINDOW.cover?(bank_window)
      raise ArgumentError, "points must be Points" unless points.is_a?(Points)

      super(pahaeng_order: order.freeze, joker_trumpable:, esmakker_banks_first:, bank_window:, points:)
    end

    def to_h = super.merge(points: points.to_h)
  end
end
