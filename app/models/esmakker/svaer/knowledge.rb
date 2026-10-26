module Esmakker
  class Svaer
    # What Svær reads from the seat's view (Round#view_for) and the bord's
    # rules, as integers (Cards): the same fields the Python port builds
    # from its observation (Knowledge.from_obs). Never another seat's cards.
    Knowledge = Struct.new(
      :seat, :phase, :hand, :rules, :melding, :bids, :can_selv, :can_med, :can_pas, :trumps, :aces, :can_turn, :can_accept,
      :kind, :melder, :trump, :called, :esmakker, :selvmakker, :turned, :vip_card, :banks, :discard_size, :discarded,
      :fordaekt_card, :fordaekt_waiting, :fordaekt_options, :tricks, :trick, :tricks_won, :legal, :players, :most_stik,
      :vaeltet, :open_hand, :kitty_cards, keyword_init: true
    ) do
      extend Cards

      def self.from_view(view, rules)
        choices = view[:choices]
        play = view[:play] || {}
        outcome = view.dig(:bidding, :outcome)
        melder = outcome && outcome[:kind] == :melder ? outcome[:melder] : nil
        sol = play[:kind] == :sol
        fordaekt = play[:fordaekt]
        acting = view[:to_act] == view[:seat]
        new(
          seat: view[:seat], phase: view[:phase].to_s, hand: ints(view[:hand]), rules:,
          melding: melding_int(view.dig(:bidding, :melding)),
          bids: choices[:meldinger].map { |code| melding_int(code) },
          can_selv: choices[:det_kan_jeg_selv], can_med: choices[:gaa_med], can_pas: choices[:pas],
          trumps: choices[:trumps].map { |code| trump_int(code) }, aces: choices[:aces].map { |letter| suit_index(letter) },
          can_turn: choices[:turn_card], can_accept: choices[:accept_trump],
          kind: melder.nil? ? nil : (sol ? "sol" : "stik"), melder:,
          trump: trump_int(play[:trump]), called: suit_index(play[:called_ace]),
          esmakker: play[:esmakker], selvmakker: play[:selvmakker] || false,
          turned: ints(play[:turned] || []), vip_card: play[:vip_card], banks: (play[:banks] || []).size,
          discard_size: acting ? play[:discard_size].to_i : 0, kitty_cards: ints(play[:kitty_cards] || []),
          discarded: sol ? [] : ints(play[:discarded] || []),
          fordaekt_card: fordaekt && fordaekt[:card] ? int(fordaekt[:card]) : nil,
          fordaekt_waiting: fordaekt ? fordaekt[:waiting] : false,
          fordaekt_options: ints(choices[:fordaekt]),
          tricks: (play[:tricks] || []).map { |stik| [ stik[:leader], plays(stik[:plays]), stik[:winner] ] },
          trick: plays(play[:current_trick] || []),
          tricks_won: play[:tricks_won] || [ 0 ] * 4,
          legal: ints(play[:legal_moves] || []),
          players: sol ? play[:players] : [], most_stik: play[:most_stik], vaeltet: sol ? play[:vaeltet] : [],
          open_hand: play[:open_hand] && ints(play[:open_hand][:cards])
        )
      end

      def self.ints(codes) = codes.map { |code| int(code) }.sort

      # A stik's plays as [seat, card]: the fordækt card face down, the
      # melder's own too (it counts as the called ace's suit).
      def self.plays(plays) = plays.map { |play| [ play[:seat], play[:fordaekt] ? FACE_DOWN : int(play[:card]) ] }
    end
  end
end
