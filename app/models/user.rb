class User < ApplicationRecord
  USERNAME_FORMAT = /\A[a-zA-Z0-9_-]+\z/
  PASSWORD_MINIMUM_LENGTH = 8

  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :approval_state, { pending: "pending", approved: "approved", rejected: "rejected", blocked: "blocked" },
    default: :pending, validate: true

  normalizes :username, with: ->(username) { username.strip }
  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :username, presence: true, length: { in: 3..20 }, format: { with: USERNAME_FORMAT },
    uniqueness: { case_sensitive: false }
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { minimum: PASSWORD_MINIMUM_LENGTH }, allow_nil: true
  validates :password, presence: true, on: :password_change

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
end
