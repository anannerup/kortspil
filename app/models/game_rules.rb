# The card game's rules a bord plays by, which the vært chooses together
# with the bord's own (TableRules); the two make up the bord's Rules. Each
# game has its own: hjerterfri's are Hjerterfri::Rules (the end score and
# the house rules), es-makker's Esmakker::Rules (the påhæng order, the
# joker and bank rules, the point values). Here a game's rules are found,
# read from the rules form and from a stored snapshot.
#
# Stored as the rules' plain hash (#to_h) in tables.rules, and snapshotted
# per spil in games.rules.
module GameRules
  BY_GAME = { "hjerterfri" => Hjerterfri::Rules, "esmakker" => Esmakker::Rules }.freeze
  GAMES = BY_GAME.keys.freeze

  module_function

  def of(game) = BY_GAME.fetch(game.to_s)

  # "Standard hjerterfri": every house rule off. Es-makker: REGLER §2.0.
  def standard(game = "hjerterfri") = of(game).standard

  # Keys missing from the stored snapshot take the standard value, and keys
  # this version does not know are dropped, so older rows keep loading.
  def from_stored(hash, game: "hjerterfri") = of(game).from_stored(hash)

  # The fields of the rules form (strong parameters).
  def form_fields(game = "hjerterfri") = of(game).form_fields

  # Whether bots may play the game (no es-makker bots in v1).
  def bots?(game) = of(game).bots?

  # Why the bord's action refuses a rules form `cast` could not read:
  # :invalid_end_score (hjerterfri) or :invalid_rules (es-makker).
  def invalid(game) = of(game)::INVALID

  # `value` as the game's rules: rules already, or the rules form (string
  # values; unticked toggles are off). An empty form is the standard rules.
  # Nil when the form holds a value the game's rules do not allow; the
  # bord's action then refuses (#invalid).
  def cast(value, game: "hjerterfri")
    rules = of(game)
    return value if value.is_a?(rules)

    form = value.to_h.transform_keys(&:to_sym)
    form.empty? ? rules.standard : rules.from_form(form)
  end
end
