# The bord's own rules, which the vært chooses together with the card
# game's (GameRules); the two make up the bord's Rules. The bord's type:
# open (listed in the lobby), password (listed, with a lock), private (not
# listed, joined by its link) or practice (an øvebord: one human and three
# bots, made by "Øvebord", never chosen). At an es-makker bord also the
# number of runder a spil lasts (REGLER §2.0 "Spillets længde"); nil at a
# hjerterfri bord, whose spil ends at its end score. Later e.g. the tur-ur.
#
# Stored in tables.kind and tables.runder; a waiting bord keeps it in its
# Rules.
class TableRules < Data.define(:kind, :runder)
  # The types a vært can choose; a practice bord is made by "Øvebord".
  CHOOSABLE_KINDS = %w[ open password private ].freeze
  LISTED_KINDS = %w[ open password ].freeze
  # The games whose spil lasts a number of runder, and how many.
  RUNDER_GAMES = %w[ esmakker ].freeze
  STANDARD_RUNDER = 10
  RUNDER = (1..50)

  def initialize(kind:, runder: nil) = super(kind: kind.to_s, runder:)

  # A new bord's: es-makker plays STANDARD_RUNDER runder.
  def self.standard(kind: "open", game: "hjerterfri") = new(kind:, runder: RUNDER_GAMES.include?(game.to_s) ? STANDARD_RUNDER : nil)

  # From the settings form: the number of runder only where the game counts
  # them. Nil when it is not a whole number in RUNDER; the action then
  # refuses (:invalid_runder).
  def self.cast(kind:, runder:, game:)
    return new(kind:) unless RUNDER_GAMES.include?(game.to_s)

    count = Integer(runder.to_s, exception: false)
    RUNDER.cover?(count) ? new(kind:, runder: count) : nil
  end

  def practice? = kind == "practice"
  def open? = kind == "open"
  def password? = kind == "password"
  def private? = kind == "private"
  def listed? = LISTED_KINDS.include?(kind)

  # Why a vært may not choose this type: it is not one a vært may choose
  # (:unknown_kind), or it is the password type without a password
  # (:password_missing), unless the bord keeps the one it has. Nil when
  # they may.
  def refusal(password, keeps_password:)
    return :unknown_kind unless CHOOSABLE_KINDS.include?(kind)

    :password_missing if password? && password.blank? && !keeps_password
  end
end
