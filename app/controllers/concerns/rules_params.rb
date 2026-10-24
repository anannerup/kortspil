# The rules a host chose in the lobby's rules form, shared by the practice
# table and the open table. With no form sent, the "Standard hjerterfri"
# preset.
module RulesParams
  extend ActiveSupport::Concern

  INVALID_END_SCORE = "Slutpoint skal være et helt tal over 0.".freeze

  private

  # The rules from the form, or nil when the end score is not a positive
  # whole number. Unticked toggles are off.
  def chosen_rules
    form = params.fetch(:rules, {}).permit(:end_score, *Hjerterfri::Rules::TOGGLES)
    return Hjerterfri::Rules.standard if form.empty?

    end_score = Integer(form[:end_score], exception: false)
    return nil unless end_score&.positive?

    toggles = Hjerterfri::Rules::TOGGLES.index_with { |toggle| form[toggle] == "1" }
    Hjerterfri::Rules.new(end_score:, **toggles)
  end
end
