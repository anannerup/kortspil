module Esmakker
  class Svaer
    # Every number docs/bots/esmakker-strategy.md §6 marks [valgt], in one
    # place so self-play can tune them (Python: SvaerParams in
    # tools/esmakker_ai/esmakker_ai/svaer.py; keep the two equal).
    Params = Data.define(
      :makker_stik, :long_ak_bonus, :nt_long_bonus,
      :nmax_margin, :gode_margin, :gode_close, :vip_margin, :vip_accept_margin, :halve_min_length,
      :p_width, :expected_bet, :sol_p,
      :nt_margin, :nt_close,
      :good_trump_count, :good_trump_honours,
      :kitty_weight, :trump_lead_factor, :overtake_factor,
      :sol_almost_low, :sol_singleton_lead, :sol_cover, :sol_middle, :sol_take, :sol_exchange_min
    ) do
      def self.standard
        new(
          # §6.2 hand estimate: makker 3½ stik (measured, Anders: "man kan næsten altid vinde 8 stik"), katten none at bidding
          makker_stik: Rational(7, 2), long_ak_bonus: Rational(1, 2), nt_long_bonus: Rational(1),
          # §6.3 meldingsrunde
          nmax_margin: Rational(1, 2), gode_margin: Rational(1), gode_close: Rational(1, 2), vip_margin: Rational(1),
          vip_accept_margin: Rational(1, 2), halve_min_length: 3,
          # P(hjem) = 1/2 + (S − N) / (2 × p_width), clamped; bet costs expected_bet stik
          p_width: Rational(2), expected_bet: Rational(1),
          # P(klaret) per sol-melding (sol, ren sol, bordlægger, ren bordlægger) when the test passes
          sol_p: [ Rational(3, 4) ] * 4,
          # §6.4 trumfløs
          nt_margin: Rational(1), nt_close: Rational(1),
          # §6.5 good trumps
          good_trump_count: 5, good_trump_honours: 2,
          # §6.1 makker guess
          kitty_weight: Rational(3, 13), trump_lead_factor: Rational(4), overtake_factor: Rational(1, 4),
          # §6.7 sol
          sol_almost_low: 6, sol_singleton_lead: 6, sol_cover: 3, sol_middle: 7, sol_take: 10,
          # §6.10 the sol exchange: only cards at least this high (sol value) are laid away
          sol_exchange_min: 10
        )
      end
    end
  end
end
