# The building blocks of the regelbog's pages (app/views/regelbog): a tip
# (a short headline that opens to its explanation, with an example hand if
# it has one), an example hand drawn with the site's own cards, and es-makker's
# point lookup table from the bord's point values.
#
# A new tip in a game's partial:
#
#   <%= tip "Giv spar dame væk", mark: :maalt, hand: "QS 4S 9H" do %>
#     <p>Forklaringen …</p>
#   <% end %>
module RegelbogHelper
  SUIT_NAMES = { "S" => "spar", "H" => "hjerter", "D" => "ruder", "C" => "klør" }.freeze
  RANK_NAMES = { "A" => "es", "K" => "konge", "Q" => "dame", "J" => "knægt", "T" => "10" }.freeze

  # How sure we are of a bot rule, as a small mark after its headline.
  MARKS = {
    maalt: [ "Målt", "pill-green", "Reglen er målt: botten vinder flere point med den end uden" ],
    skoen: [ "Tal justeres", "pill-amber", "Et skøn, der stadig justeres, når botterne bliver målt" ],
    anders: [ "Anders", "pill-blue", "Besluttet af Anders" ]
  }.freeze

  # A tip: the headline is always shown, the body (the block) opens on a
  # tap. `hand` is an example hand by card codes ("AS KS X1"); `caption`
  # says what to look at in it.
  def tip(title, mark: nil, hand: nil, caption: nil, &block)
    tag.details(class: "tip") do
      summary = tag.summary { safe_join([ tag.span(title, class: "tip-title"), tip_mark(mark) ].compact, " ") }
      body = tag.div(class: "tip-body") { safe_join([ capture(&block), (example_hand(hand, caption:) if hand) ].compact) }
      summary + body
    end
  end

  # An example hand. The cards are drawn by the site's card components
  # (app/frontend/regelbog); without JavaScript the cards are named in words.
  # Codes as the server sends them: rank + suit ("TD", "QS"), jokers "X1".
  def example_hand(codes, caption: nil)
    cards = codes.split
    words = cards.map { |code| card_words(code) }.join(", ")
    tag.figure(class: "regelbog-hand") do
      hand = tag.div(words, class: "regelbog-cards", role: "group", aria: { label: words }, data: { card_hand: cards.join(" ") })
      caption ? hand + tag.figcaption(caption) : hand
    end
  end

  # "spar dame", "hjerter 10", "joker".
  def card_words(code)
    return "joker" if code.start_with?("X")

    "#{SUIT_NAMES.fetch(code[1])} #{RANK_NAMES.fetch(code[0], code[0])}"
  end

  # Es-makker's lookup table (REGLER §2.0 "Opslagstabel"), from the bord's
  # point values: per melding in the ladder's order, what each loser pays
  # each winner when it goes home with 0–5 overstik. Rows are
  # [name, [amount or nil, …]]; nil where the overstik cannot be had.
  def esmakker_lookup_rows(points)
    sol_after = { 9 => [ "Sol", points.sol ], 10 => [ "Ren sol", points.ren_sol ], 11 => [ "Bordlægger", points.bordlaegger ], 12 => [ "Ren bordlægger", points.ren_bordlaegger ] }
    Esmakker::Points::NUMBERS.flat_map do |number|
      stake = points.stakes.fetch(number)
      overstik = (0..5).map { |extra| number.to_i + extra <= 13 ? extra : nil }
      rows = [
        [ number, overstik.map { |extra| extra && stake + extra } ],
        [ "#{number}p", overstik.map { |extra| extra && (stake + extra) * points.pahaeng } ]
      ]
      sol = sol_after[number.to_i]
      sol ? rows << [ sol.first, [ sol.last, *Array.new(5) ] ] : rows
    end
  end

  # 1.5 as "1,5", 2.0 as "2".
  def point_amount(value)
    return "–" if value.nil?

    number_with_precision(value, precision: 1, strip_insignificant_zeros: true, separator: ",")
  end

  private

  def tip_mark(mark)
    return nil unless mark

    label, color, title = MARKS.fetch(mark)
    tag.span(label, class: "pill #{color} tip-mark", title:)
  end
end
