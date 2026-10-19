module Hjerterfri
  # The outcome of Round#apply: the next round, or the reason the intent was rejected.
  class Result < Data.define(:round, :reason)
    def self.accepted(round) = new(round:, reason: nil)
    def self.rejected(reason) = new(round: nil, reason:)

    def accepted? = reason.nil?
    def rejected? = !accepted?
  end
end
