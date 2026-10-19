# The "Venner" page: search, requests and the friends list.
class FriendshipsController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @search_results = Current.user.befriendable_users(@query).order(:username).limit(20)
    @incoming = Current.user.received_friendships.pending.includes(:requester).order(:created_at)
    @outgoing = Current.user.sent_friendships.pending.includes(:addressee).order(:created_at)
    @friendships = Current.user.friendships.accepted.includes(:requester, :addressee)
      .sort_by { |friendship| friendship.other_user(Current.user).username.downcase }
  end

  def create
    friendship = Current.user.sent_friendships.new(addressee: User.find(params.expect(:addressee_id)))

    if friendship.save
      redirect_to friendships_path, notice: "Venneanmodning sendt til #{friendship.addressee.username}"
    else
      redirect_to friendships_path, alert: friendship.errors.full_messages.to_sentence
    end
  end

  # Accepts an incoming request.
  def update
    friendship = Current.user.received_friendships.pending.find(params[:id])
    friendship.accept!
    redirect_to friendships_path, notice: "Du er nu ven med #{friendship.requester.username}"
  end

  # Declines an incoming request, withdraws an outgoing one or removes a friend.
  def destroy
    friendship = Current.user.friendships.find(params[:id])
    friendship.destroy!
    redirect_to friendships_path, notice: destroy_notice(friendship)
  end

  private
    def destroy_notice(friendship)
      other = friendship.other_user(Current.user).username

      if friendship.accepted?
        "#{other} er fjernet fra dine venner"
      elsif friendship.requester == Current.user
        "Venneanmodningen til #{other} er trukket tilbage"
      else
        "Venneanmodningen fra #{other} er afvist"
      end
    end
end
