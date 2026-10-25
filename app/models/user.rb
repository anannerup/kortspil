class User < ApplicationRecord
  USERNAME_FORMAT = /\A[a-zA-Z0-9_-]+\z/
  PASSWORD_MINIMUM_LENGTH = 8

  has_secure_password
  # A user counts as online while a NotificationsChannel subscription keeps
  # refreshing last_seen_at (see NotificationsChannel::HEARTBEAT_INTERVAL).
  ONLINE_WINDOW = 1.minute

  has_many :sessions, dependent: :destroy
  has_many :sent_friendships, class_name: "Friendship", foreign_key: :requester_id,
    inverse_of: :requester, dependent: :destroy
  has_many :received_friendships, class_name: "Friendship", foreign_key: :addressee_id,
    inverse_of: :addressee, dependent: :destroy

  enum :approval_state, { pending: "pending", approved: "approved", rejected: "rejected", blocked: "blocked" },
    default: :pending, validate: true

  scope :alphabetically, -> { order(Arel.sql("lower(username)")) }

  normalizes :username, with: ->(username) { username.strip }
  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :username, presence: true, length: { in: 3..20 }, format: { with: USERNAME_FORMAT },
    uniqueness: { case_sensitive: false }
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { minimum: PASSWORD_MINIMUM_LENGTH }, allow_nil: true
  validates :password, presence: true, on: :password_change

  scope :online, -> { where(last_seen_at: ONLINE_WINDOW.ago..) }
  scope :wanting_password_reset, -> { where.not(password_reset_requested_at: nil).order(:password_reset_requested_at) }
  scope :username_containing, ->(query) {
    where("lower(username) LIKE ?", "%#{sanitize_sql_like(query.to_s.strip.downcase)}%")
  }

  # Finds a user by username (case-insensitive) or email address.
  def self.find_by_login(login)
    login = login.to_s.strip
    return if login.blank?

    if login.include?("@")
      find_by(email_address: login.downcase)
    else
      where("lower(username) = ?", login.downcase).first
    end
  end

  # Like authenticate_by, but the login may be a username or an email address.
  def self.authenticate_by_login(login, password)
    user = find_by_login(login)
    return user if user&.authenticate(password)

    # Hash anyway so response time doesn't reveal whether the login exists.
    new(password: password.to_s) unless user
    nil
  end

  def awaiting_approval?
    pending? || rejected?
  end

  # Blocking ends every session, so the user is out immediately, not on next login.
  def block!
    transaction do
      blocked!
      sessions.destroy_all
    end
  end

  # "Glemt adgangskode?": the admin sees the request on the admin page.
  def request_password_reset! = touch(:password_reset_requested_at)

  # Used when the admin sets a new password: old sessions end with the old
  # password, and a pending reset request is done.
  def reset_password(password:, password_confirmation: nil)
    assign_attributes(password:, password_confirmation:, password_reset_requested_at: nil)
    transaction do
      save(context: :password_change).tap { |saved| sessions.destroy_all if saved }
    end
  end

  def friendships
    Friendship.involving(self)
  end

  def friends
    User.where(id: friendships.accepted.select(:requester_id))
      .or(User.where(id: friendships.accepted.select(:addressee_id)))
      .where.not(id: id)
  end

  # Approved users this user could send a friend request to: everyone except
  # themself and anyone they already have a friendship or request with.
  def befriendable_users(query)
    return User.none if query.to_s.strip.empty?

    User.approved.username_containing(query)
      .where.not(id: id)
      .where.not(id: friendships.select(:requester_id))
      .where.not(id: friendships.select(:addressee_id))
  end

  # The bord this user sits at, if it isn't closed: one that has not
  # started yet (a WaitingTable, in memory) or a stored one (indexed on
  # seats.user_id). "Spil" in the top bar links there with a "Ved bordet"
  # marker.
  def current_table
    WaitingTables.default.seated(self) || Table.with_seated(self).where.not(status: :closed).order(id: :desc).first
  end

  def online?
    last_seen_at.present? && last_seen_at >= ONLINE_WINDOW.ago
  end

  def mark_online!
    update_column :last_seen_at, Time.current
  end

  def mark_offline!
    update_column :last_seen_at, nil
  end

  # Presence for the friends list: friends hear when this user comes
  # online (not on every heartbeat) and when they leave.
  def come_online!
    was_online = online?
    mark_online!
    broadcast_presence unless was_online
  end

  def go_offline!
    mark_offline!
    broadcast_presence
  end

  def broadcast_presence
    friends.each { |friend| NotificationsChannel.broadcast_to friend, type: "presence", user_id: id, online: online? }
  end
end
