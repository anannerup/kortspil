# A spil at a table: the rules it is played with, who sits where, and its
# runder. Live state is rebuilt from these rows (see TableCommands).
#
# A finished spil keeps its final totals in `final_scores`. A spil abandoned
# because a player left keeps the totals of its completed runder there and
# records who left in `forfeited_by`: leaving before the end loses the spil.
#
# `seats` holds four entries in seat order, as they were at the start:
# { "kind" => "human", "user_id" => 7 } or { "kind" => "bot", "name" => "Bot 1" }.
class Game < ApplicationRecord
  belongs_to :table
  belongs_to :forfeited_by, class_name: "User", optional: true
  has_many :rounds, -> { order(:number) }, dependent: :destroy, inverse_of: :game

  enum :status, { in_progress: "in_progress", finished: "finished", abandoned: "abandoned" }, validate: true

  validate :four_seats

  def self.human_seat(user) = { "kind" => "human", "user_id" => user.id }
  def self.bot_seat(name) = { "kind" => "bot", "name" => name }

  def current_round = rounds.last

  # The engine's view of the spil: the points of every completed runde.
  def engine_game
    rules = engine_rules
    results = rounds.map { |round| round.to_engine(rules) }.select(&:complete?).map(&:points)
    Hjerterfri::Game.new(rules:, results:)
  end

  # The seat index the user sits in, or nil if they don't sit here.
  def seat_of(user)
    seats.index { |seat| seat["kind"] == "human" && seat["user_id"] == user.id }
  end

  def bot?(seat) = seats.fetch(seat)["kind"] == "bot"

  # { seat index => user id } for the seats humans sit in.
  def human_seats
    seats.each_with_index.filter_map { |seat, index| [ index, seat["user_id"] ] if seat["kind"] == "human" }.to_h
  end

  # Who sits where, for display: [{ seat:, name:, bot: }].
  def seat_names
    usernames = User.where(id: human_seats.values).pluck(:id, :username).to_h
    seats.each_with_index.map do |seat, index|
      bot = seat["kind"] == "bot"
      { seat: index, name: bot ? seat["name"] : usernames[seat["user_id"]], bot: }
    end
  end

  # The engine's rules config. Keys missing from the stored snapshot take the
  # standard value, so older games keep loading when toggles are added.
  def engine_rules
    known = rules.symbolize_keys.slice(*Hjerterfri::Rules.members)
    Hjerterfri::Rules.standard.with(**known)
  end

  private

  def four_seats
    errors.add(:seats, "must hold #{Hjerterfri::Deal::SEAT_COUNT} seats") unless seats.size == Hjerterfri::Deal::SEAT_COUNT
  end
end
