class Table
  # What an action at a bord came to. The bord decides: it accepts, and the
  # outcome holds the messages for each human seat (Message), or it refuses
  # with a reason, and nothing changed. A refusal is a symbol whose text is
  # tables.refusals.* in the locale (#refusal_message). `table` is the bord
  # after the action: a WaitingTable or a stored Table (after "Start spil"
  # the stored one), or nil when there is none.
  #
  # Controllers and channels only render it; nothing here touches HTTP or
  # Action Cable.
  Outcome = Data.define(:table, :messages, :refusal) do
    def initialize(table:, messages: [], refusal: nil) = super

    def refused? = !refusal.nil?
    def accepted? = refusal.nil?

    def refusal_message = refused? ? I18n.t("tables.refusals.#{refusal}") : nil
  end
end
