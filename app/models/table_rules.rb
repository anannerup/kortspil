# The bord's own rules, which the vært chooses together with the card
# game's (GameRules); the two make up the bord's Rules. For now that is the
# bord's type: open (listed in the lobby), password (listed, with a lock),
# private (not listed, joined by its link) or practice (an øvebord: one
# human and three bots, made by "Øvebord", never chosen). Later e.g. the
# number of runder or the tur-ur.
#
# Stored in tables.kind; a waiting bord keeps it in its Rules.
class TableRules < Data.define(:kind)
  # The types a vært can choose; a practice bord is made by "Øvebord".
  CHOOSABLE_KINDS = %w[ open password private ].freeze
  LISTED_KINDS = %w[ open password ].freeze

  def initialize(kind:) = super(kind: kind.to_s)

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
