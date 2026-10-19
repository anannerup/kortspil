# The "Afventer godkendelse" page: the only page pending and rejected users can see.
class ApprovalsController < ApplicationController
  allow_unapproved_access

  def show
    redirect_to root_path unless Current.user.awaiting_approval?
  end
end
