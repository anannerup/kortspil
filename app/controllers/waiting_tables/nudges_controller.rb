# Puf (ticket 16). The vært nudges a friend to the bord (create) or
# withdraws a pending puf (destroy); the nudged friend answers (update,
# `answer` "accept" or "decline"). Accepting seats the friend and opens the
# bord; the friend's notification sends it as JSON.
class WaitingTables::NudgesController < WaitingTables::BaseController
  def create
    render_outcome @table.nudge(user: Current.user, friend: User.find_by(id: params[:friend_id]))
  end

  def destroy
    render_outcome @table.withdraw_nudge(user: Current.user, nudge_id:)
  end

  def update
    accept = params[:answer] == "accept"
    outcome = @table.answer_nudge(user: Current.user, nudge_id:, accept:)
    return render_outcome(outcome) if outcome.refused? || accept

    respond_to do |format|
      format.html { redirect_back_or_to root_path }
      format.json { render json: { declined: true } }
    end
  end

  private

  def nudge_id = Integer(params[:id].to_s, exception: false)
end
