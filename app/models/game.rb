# A spil at a table: the rules it is played with, who sat where when it
# started, and its runder. Live state is rebuilt from these rows by
# LiveGame; who sits where now is the table's Seating.
#
# A finished spil keeps its final totals in `final_scores`. A spil abandoned
# because a player left keeps the totals of its completed runder there and
# records who left in `forfeited_by`: leaving before the end loses the spil.
#
# `seats` is the snapshot taken at the start and never changes: four
# entries in seat order, { "kind" => "human", "user_id" => 7 } or
# { "kind" => "bot", "name" => "Bot 1" }. Later changes are appended to
# `seat_log` as { seat, from, to, at_play } (Table::Seating#take_over!), so
# a replay knows who held each seat at every step.
class Game < ApplicationRecord
  belongs_to :table
  belongs_to :forfeited_by, class_name: "User", optional: true
  has_many :rounds, -> { order(:number) }, dependent: :destroy, inverse_of: :game

  enum :status, { in_progress: "in_progress", finished: "finished", abandoned: "abandoned" }, validate: true

  validate :four_seats

  def current_round = rounds.last

  # The engine's rules config. Keys missing from the stored snapshot take the
  # standard value, so older games keep loading when toggles are added.
  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  private

  def four_seats
    errors.add(:seats, "must hold #{Hjerterfri::Deal::SEAT_COUNT} seats") unless seats.size == Hjerterfri::Deal::SEAT_COUNT
  end
end
