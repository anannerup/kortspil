module Hjerterfri
  # A moon shooter's choice under shooter's choice: "add_to_others" (26 to
  # every other seat) or "subtract_from_self" (−26 to the shooter).
  class MoonChoice < Data.define(:option)
    OPTIONS = %w[add_to_others subtract_from_self].freeze
  end
end
