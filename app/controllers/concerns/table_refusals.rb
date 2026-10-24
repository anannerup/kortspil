# Answers a table command the bord refused (TableCommands::Outcome#refusal)
# with its message, on the page the user came from.
module TableRefusals
  extend ActiveSupport::Concern

  private

  def refused(outcome)
    redirect_back_or_to root_path, alert: t("tables.refusals.#{outcome.refusal}")
  end
end
