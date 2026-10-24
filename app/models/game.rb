# A spil at a table: the rules it is played with, who sat where when it
# started, and its runder. Live state is rebuilt from these rows by
# LiveGame; who sits where now is the table's Seating.
#
# A finished spil keeps its final totals in `final_scores`. A spil afbrudt
# (abandoned) because its last human left keeps the totals of its completed
# runder there and records that player in `forfeited_by`.
#
# `seats` is the snapshot taken at the start and never changes: four
# entries in seat order, { "kind" => "human", "user_id" => 7 } or
# { "kind" => "bot", "name" => "Bot 1" }. Later changes are appended to
# `seat_log` as { seat, from, to, at_play } (Table::Seating#take_over!), so
# a replay knows who held each seat at every step.
#
# The result (GLOSSARY.md: Forlade, Vinder, Afbrudt): every player who
# forlod the spil lost it, whatever their points (#forladt_ids). Once it is
# finished, the vindere are the humans still in their seats with the lowest
# total; a human tied with a bot wins, a bot never does (#winner_ids). A
# spil abandoned because its last human left is afbrudt: no vinder.
class Game < ApplicationRecord
  belongs_to :table
  belongs_to :forfeited_by, class_name: "User", optional: true
  has_many :rounds, -> { order(:number) }, dependent: :destroy, inverse_of: :game

  enum :status, { in_progress: "in_progress", finished: "finished", abandoned: "abandoned" }, validate: true

  validate :four_seats

  def current_round = rounds.last

  # Who holds each seat now: the start snapshot with the seat_log applied.
  def holders
    seats.each_with_index.map do |start, seat|
      taken = seat_log.reverse.find { |entry| entry["seat"] == seat }
      taken ? { "kind" => "bot", "name" => taken["to"] } : start
    end
  end

  # The seats a human holds now.
  def human_seats = holders.each_with_index.filter_map { |holder, seat| seat if holder["kind"] == "human" }

  # The players who forlod the spil: a bot took their seat, or they were
  # the last human and left. Each of them lost it.
  def forladt_ids = [ *seat_log.map { |entry| entry["from"] }, forfeited_by_id ].compact.uniq

  # The vindere of a finished spil, as user ids (see above).
  def winner_ids
    return [] unless finished?

    lowest = final_scores.min
    now = holders
    human_seats.select { |seat| final_scores[seat] == lowest }.map { |seat| now[seat]["user_id"] }
  end

  # The engine's rules config. Keys missing from the stored snapshot take the
  # standard value, so older games keep loading when toggles are added.
  def engine_rules = Hjerterfri::Rules.from_stored(rules)

  private

  def four_seats
    errors.add(:seats, "must hold #{Hjerterfri::Deal::SEAT_COUNT} seats") unless seats.size == Hjerterfri::Deal::SEAT_COUNT
  end
end
