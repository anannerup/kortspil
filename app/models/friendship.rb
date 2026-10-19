# A mutual friendship between two approved users. It starts as a pending
# request from the requester to the addressee and becomes accepted when the
# addressee accepts. Declining, withdrawing and removing all delete the row.
class Friendship < ApplicationRecord
  belongs_to :requester, class_name: "User"
  belongs_to :addressee, class_name: "User"

  enum :state, { pending: "pending", accepted: "accepted" }, default: :pending, validate: true

  validate :not_with_self
  validate :both_users_approved, on: :create
  validate :pair_not_taken, on: :create

  scope :involving, ->(user) { where(requester: user).or(where(addressee: user)) }
  scope :between, ->(user, other) { where(requester: user, addressee: other).or(where(requester: other, addressee: user)) }

  after_create_commit :notify_addressee

  def accept!
    accepted!
  end

  # The other user in the friendship, seen from +user+.
  def other_user(user)
    requester_id == user.id ? addressee : requester
  end

  private
    def not_with_self
      errors.add(:base, "Du kan ikke være ven med dig selv") if requester_id.present? && requester_id == addressee_id
    end

    def both_users_approved
      return if requester.nil? || addressee.nil?

      errors.add(:base, "Brugeren kan ikke findes") unless requester.approved? && addressee.approved?
    end

    def pair_not_taken
      return if requester.nil? || addressee.nil?

      existing = Friendship.between(requester, addressee).first
      return unless existing

      if existing.accepted?
        errors.add(:base, "I er allerede venner")
      elsif existing.requester_id == requester_id
        errors.add(:base, "Du har allerede sendt en venneanmodning til #{addressee.username}")
      else
        errors.add(:base, "#{addressee.username} har allerede sendt dig en venneanmodning")
      end
    end

    def notify_addressee
      NotificationsChannel.broadcast_to addressee,
        type: "friend_request", friendship_id: id, from: requester.username
    end
end
