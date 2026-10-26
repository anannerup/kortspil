# One of a bord's four seats as stored: empty, a human's (user) or a bot's
# (bot_name, with the bot's level: bot_level, one of Hjerterfri::Bot::LEVELS).
# Read and changed through Table::Seating.
class Seat < ApplicationRecord
  belongs_to :table
  belongs_to :user, optional: true

  validates :position, inclusion: { in: 0...Table::Seating::SEAT_COUNT }, uniqueness: { scope: :table_id }
  validates :bot_level, inclusion: { in: Hjerterfri::Bot::LEVELS.map(&:to_s) }, if: :bot_name
  validates :bot_level, absence: true, unless: :bot_name
  validate :one_occupant

  after_commit -> { table&.refresh_lobby }

  scope :occupied_by, ->(user) { where(user_id: user.id) }

  private

  def one_occupant
    errors.add(:bot_name, "must be empty when a user sits here") if user_id && bot_name
  end
end
