# The card game's rules a bord plays by, which the vært chooses together
# with the bord's own (TableRules); the two make up the bord's Rules. Each
# game has its own: hjerterfri's are Hjerterfri::Rules (the end score and
# the house rules); es-makker's come later. Here a game's rules are found,
# read from the lobby's rules form and from a stored snapshot.
#
# Stored as the rules' plain hash (#to_h) in tables.rules, and snapshotted
# per spil in games.rules.
module GameRules
  BY_GAME = { "hjerterfri" => Hjerterfri::Rules }.freeze

  module_function

  def of(game) = BY_GAME.fetch(game.to_s)

  # "Standard hjerterfri": every house rule off.
  def standard(game = "hjerterfri") = of(game).standard

  # Keys missing from the stored snapshot take the standard value, and keys
  # this version does not know are dropped, so older rows keep loading.
  def from_stored(hash, game: "hjerterfri") = of(game).from_stored(hash)

  # The fields of the rules form.
  def form_fields(game = "hjerterfri") = [ :end_score, *of(game)::TOGGLES ]

  # `value` as the game's rules: rules already, or the rules form (string
  # values; unticked toggles are off). An empty form is the standard rules.
  # Nil when the form's end score is not a positive whole number; the
  # bord's action then refuses (:invalid_end_score).
  def cast(value, game: "hjerterfri")
    rules = of(game)
    return value if value.is_a?(rules)

    form = value.to_h.transform_keys(&:to_sym)
    return rules.standard if form.empty?

    end_score = Integer(form[:end_score], exception: false)
    return nil unless end_score&.positive?

    rules.new(end_score:, **rules::TOGGLES.index_with { |toggle| form[toggle] == "1" })
  end
end
