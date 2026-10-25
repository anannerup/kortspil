class ApplicationController < ActionController::Base
  include Authentication
  include Navigation
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  # Renders what an action at a bord came to (Table::Outcome); the bord
  # decided. Accepted: back to the bord's page, or, when the page itself
  # asked (JSON), the bord as its page shows it, so it updates at once.
  def render_outcome(outcome, notice: nil, refused_to: root_path)
    return render_refusal(outcome, refused_to:) if outcome.refused?

    respond_to do |format|
      format.html { redirect_to polymorphic_path(outcome.table), notice: }
      format.json { render json: { table: outcome.table.reload.lobby_entry } }
    end
  end

  # A refused action is answered with the refusal's message, on the page
  # the user came from (else `refused_to`) or as JSON.
  def render_refusal(outcome, refused_to: root_path)
    respond_to do |format|
      format.html { redirect_back_or_to refused_to, alert: outcome.refusal_message }
      format.json { render json: { error: outcome.refusal_message }, status: :unprocessable_entity }
    end
  end
end
