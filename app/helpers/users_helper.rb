module UsersHelper
  APPROVAL_STATE_PILLS = { "approved" => "pill-green", "pending" => "pill-amber", "blocked" => "pill-orange" }.freeze

  # A round badge with the user's first letter, tinted per user so a list of
  # people is easy to scan. Pass a block to put something on it (presence).
  def user_avatar(user, &block)
    tag.span(class: [ "avatar", "avatar-#{user.id % 5}" ], aria: { hidden: true }) do
      safe_join([ user.username.first, (capture(&block) if block) ])
    end
  end

  def approval_state_pill(user)
    tag.span t(user.approval_state, scope: "approval_states"),
      class: [ "pill", "status", APPROVAL_STATE_PILLS[user.approval_state] ]
  end
end
