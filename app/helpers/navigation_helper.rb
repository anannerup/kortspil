module NavigationHelper
  # "Spil" goes back to the user's bord when they sit at one, else the lobby.
  def spil_path
    table = Current.user.current_table
    table ? polymorphic_path(table) : root_path
  end

  # Computed once per request; shown on both "Konto" and "Venner".
  def pending_friend_requests_count
    @pending_friend_requests_count ||= Current.user.received_friendships.pending.count
  end

  def friend_requests_badge
    count = pending_friend_requests_count
    tag.span(count, class: "badge", title: "Venneanmodninger") if count.positive?
  end

  def nav_tab_class(area)
    class_names("tab", "tab-active": navigation_area == area)
  end

  def nav_aria_current(active)
    active ? "page" : nil
  end

  # Which Konto sub-page the current controller is.
  def konto_section
    case controller_path
    when "friendships" then :venner
    when "passwords" then :adgangskode
    when %r{\Aadmin/} then :admin
    end
  end

  def back_link(text, path)
    tag.p(link_to("← #{text}", path), class: "back-link")
  end
end
