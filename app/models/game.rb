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
#
# Once finished, `play_again_by` collects the users who chose "Spil igen";
# the next spil starts when every human at the table has.
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

  # The user chose "Spil igen" after this spil.
  def ask_to_play_again!(user)
    update!(play_again_by: play_again_by | [ user.id ]) unless play_again_by.include?(user.id)
  end

  # Whether every human in `seating` (Table::Seating) has chosen "Spil igen".
  def everyone_asked_to_play_again?(seating)
    seating.occupants.select(&:human?).all? { |human| play_again_by.include?(human.user_id) }
  end

  # The seats in `seating` whose human has chosen "Spil igen".
  def play_again_seats(seating)
    seating.occupants.select { |occupant| occupant.human? && play_again_by.include?(occupant.user_id) }.map(&:seat)
  end

  private

  def four_seats
    errors.add(:seats, "must hold #{Hjerterfri::Deal::SEAT_COUNT} seats") unless seats.size == Hjerterfri::Deal::SEAT_COUNT
  end
end
