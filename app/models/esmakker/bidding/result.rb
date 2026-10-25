module Esmakker
  class Bidding
    # The outcome of Bidding#apply: the next bidding, or the reason the
    # intent was rejected.
    class Result < Data.define(:bidding, :reason)
      def self.accepted(bidding) = new(bidding:, reason: nil)
      def self.rejected(reason) = new(bidding: nil, reason:)

      def accepted? = reason.nil?
      def rejected? = !accepted?
    end
  end
end
