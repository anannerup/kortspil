class Table
  # A payload for the human in `seat` (user `user_id`), part of an Outcome.
  # Callers broadcast it (TableChannel.deliver).
  Message = Data.define(:seat, :user_id, :payload)
end
