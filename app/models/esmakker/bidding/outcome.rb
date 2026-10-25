module Esmakker
  class Bidding
    # How a finished meldingsrunde ended.
    #
    # - kind :melder: melder won with melding; went_with lists the seats that
    #   went with it (nolo only), in the order they went with.
    # - kind :redeal: a new deal, because everyone passed (reason
    #   :all_passed) or a jernhånd was claimed (reason :jernhaand). dealer is
    #   the seat that must deal it: after all pass, the former forhånd loses
    #   the forhånd and deals; after a jernhånd, the same kortgiver deals
    #   again.
    class Outcome < Data.define(:kind, :melder, :melding, :went_with, :reason, :dealer)
      def self.melder(melder, melding, went_with)
        new(kind: :melder, melder:, melding:, went_with: went_with.freeze, reason: nil, dealer: nil)
      end

      def self.redeal(reason, dealer)
        new(kind: :redeal, melder: nil, melding: nil, went_with: [].freeze, reason:, dealer:)
      end

      def redeal? = kind == :redeal

      def to_h
        { kind:, melder:, melding: melding&.to_s, went_with:, reason:, dealer: }
      end
    end
  end
end
