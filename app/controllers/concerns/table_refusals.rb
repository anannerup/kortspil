# Answers a table command: on success, back to the table page, or, when the
# table page itself asked (JSON), the bord as its page shows it
# (Table#lobby_entry or WaitingTable#lobby_entry), so it updates at once. A command the bord refused
# (TableCommands::Outcome#refusal) is answered with its message, on the
# page the user came from or as JSON.
module TableRefusals
  extend ActiveSupport::Concern

  private

  def answer(outcome, notice: nil)
    return refused(outcome) if outcome.refused?

    respond_to do |format|
      format.html { redirect_to polymorphic_path(outcome.table), notice: }
      format.json { render json: { table: outcome.table.reload.lobby_entry } }
    end
  end

  def refused(outcome) = refuse_with(t("tables.refusals.#{outcome.refusal}"))

  def refuse_with(message, html_to: nil)
    respond_to do |format|
      format.html { html_to ? redirect_to(html_to, alert: message) : redirect_back_or_to(root_path, alert: message) }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end
end
