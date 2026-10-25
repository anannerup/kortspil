class TableCommands
  # The commands for a bord before its spil (a WaitingTable, in memory):
  # make a bord or a practice bord, sit, stand up, the vært's kick, bots,
  # settings and pufs, a friend's answer to a puf, and the start, which
  # stores the bord, its seats and the spil in one transaction. Nothing
  # here writes to the database before the start.
  #
  # Each change runs under the registry's lock (WaitingTables#change),
  # first letting pufs whose time is up expire (the injected clock), and
  # returns an Outcome whose table is the bord as it is after the change.
  # A command for a bord that has started or closed is refused
  # (:not_waiting).
  module BeforeStart
    # Makes a practice bord with the rules the user chose, the user in seat
    # 0 and three bots. Like any bord it waits for its start: the user may
    # change the rules first. Refused while the user sits at another bord.
    def start_practice(user:, rules: Hjerterfri::Rules.standard)
      return Outcome.new(table: nil, refusal: :seated_elsewhere) if user.current_table

      Outcome.new(table: @waiting_tables.add(WaitingTable.create(host: user, kind: :practice, rules:)))
    end

    # Makes a bord for `game` (chosen in the lobby; WaitingTable::GAMES) of
    # the type the user chose (Table::CHOOSABLE_KINDS; a password table with
    # its password) with their rules and the user as vært in seat 0.
    # Refused while the user sits at another bord.
    def create_table(user:, rules: Hjerterfri::Rules.standard, kind: "open", password: nil, game: "hjerterfri")
      refusal = :game_not_available unless WaitingTable::GAMES.include?(game.to_s)
      refusal ||= kind_refusal(kind.to_s, password, keeps_password: false)
      refusal ||= :seated_elsewhere if user.current_table
      return Outcome.new(table: nil, refusal:) if refusal

      Outcome.new(table: @waiting_tables.add(WaitingTable.create(host: user, kind:, rules:, password:, game: game.to_s)))
    end

    # The user takes the free seat `seat`, or moves there if they sit at the
    # bord already (see WaitingTable#refusal_to_sit). One bord per user.
    def sit(table:, user:, seat:, password: nil)
      waiting_change(table) do |current|
        refusal = :seated_elsewhere if seated_elsewhere?(user, current)
        refusal ||= current.refusal_to_sit(user, seat, password:)
        refusal ? [ current, refusal ] : [ current.sit(user, seat), nil ]
      end
    end

    # The vært kicks the player in `seat`. It is not a ban: they may sit
    # down again. Bots are removed with #remove_bot, and the vært stands up
    # instead of kicking themself.
    def kick(table:, user:, seat:)
      host_changes_seat(table, user, seat) do |current|
        occupant = current.occupants.fetch(seat)
        next [ current, :nobody_to_kick ] unless occupant.human? && occupant.user_id != user.id

        [ current.empty(seat), nil ]
      end
    end

    # The vært puts a bot in the empty seat `seat`.
    def add_bot(table:, user:, seat:)
      host_changes_seat(table, user, seat) { |current| current.add_bot(seat) }
    end

    # The vært takes the bot in `seat` out again.
    def remove_bot(table:, user:, seat:)
      host_changes_seat(table, user, seat) do |current|
        next [ current, :no_bot_there ] unless current.occupants.fetch(seat).bot?

        [ current.empty(seat), nil ]
      end
    end

    # The vært changes the rules and the table type. A password table needs
    # a password; left blank, it keeps the one it has. Leaving the password
    # type drops the password. A practice bord stays one: only its rules
    # change, whatever `kind` says. The game is not a setting.
    def change_settings(table:, user:, rules:, kind: nil, password: nil)
      waiting_change(table) do |current|
        refusal = host_refusal(current, user)
        refusal ||= kind_refusal(kind.to_s, password, keeps_password: current.password?) unless current.practice?
        refusal ? [ current, refusal ] : [ current.with_settings(rules:, kind: kind.to_s, password:), nil ]
      end
    end

    # The vært nudges `friend` to the bord (WaitingTable#nudge for the cap).
    # Only friends, only by the vært, not at a practice bord.
    def nudge(table:, user:, friend:)
      waiting_change(table) do |current|
        refusal = host_refusal(current, user)
        refusal ||= :practice_seats if current.practice?
        refusal ||= :not_friend unless friend && user.friends.exists?(friend.id)
        refusal ? [ current, refusal ] : current.nudge(friend, now:)
      end
    end

    # The vært withdraws a pending puf, which frees its seat.
    def withdraw_nudge(table:, user:, nudge_id:)
      waiting_change(table) do |current|
        refusal = host_refusal(current, user)
        refusal ? [ current, refusal ] : current.withdraw(nudge_id)
      end
    end

    # The nudged friend accepts (and is seated in a free seat, without the
    # password) or declines. Accepting is refused while they sit at another
    # bord; the puf stays pending.
    def answer_nudge(table:, user:, nudge_id:, accept:)
      waiting_change(table) do |current|
        next [ current, :seated_elsewhere ] if accept && seated_elsewhere?(user, current)

        current.answer(nudge_id, user, accept:)
      end
    end

    # Lets pufs whose time is up expire, so everyone sees it; the bord's
    # page asks when the next one is due.
    def expire_nudges(table:)
      waiting_change(table) { |current| [ current, nil ] }
    end

    # The vært starts the spil once every seat is taken: the bord, its seat
    # rows and the spil are stored in one transaction, the first runde is
    # dealt, and every seat gets its state. Pending pufs end with it. The
    # table chat comes along. The Outcome's table is the stored table.
    def start(table:, user:)
      return Outcome.new(table:, refusal: :not_waiting) unless table.is_a?(WaitingTable)

      live = nil
      outcome = waiting_change(table) do |current|
        refusal = host_refusal(current, user) || (:seats_not_filled unless current.full?)
        next [ current, refusal ] if refusal

        live = store(current)
        [ nil, nil ]
      end
      return outcome if outcome.refused?

      runde_started(live)
    end

    private

    # Under the registry's lock: the stored table with its seats and the
    # spil's first runde, as a LiveGame.
    def store(waiting)
      live = Table.transaction do
        stored = Table.create!(host_id: waiting.host_id, kind: waiting.kind, password_digest: waiting.password_digest, rules: waiting.rules, status: :playing)
        stored.seating.seat_everyone!(waiting.occupants).heard_from_all!(at: now)
        LiveGame.start(table: stored, rules: stored.engine_rules, shuffler: @shuffler)
      end
      @chat.move(waiting.id, live.game.table_id)
      @waiting_tables.started!(waiting.id, live.game.table_id)
      live
    end

    # Standing up before the start. The bord closes when no human is left
    # (a practice bord, always), and its chat goes with it.
    def stand(table:, user:)
      waiting_change(table) do |current|
        after = current.stand(user.id)
        next [ after, nil ] if after.humans.any?

        @chat.forget(current.id)
        [ nil, nil ]
      end
    end

    # Runs a change to the bord as it is now, under the registry's lock,
    # with pufs whose time is up expired. The block returns [bord after,
    # refusal]; on a refusal the expiries still count.
    def waiting_change(table)
      return Outcome.new(table:, refusal: :not_waiting) unless table.is_a?(WaitingTable)

      after = nil
      refusal = @waiting_tables.change(table.id) do |current|
        next [ nil, :not_waiting ] unless current

        current = current.expire_nudges(now)
        after, refused = yield(current)
        [ refused ? current : after, refused ]
      end
      Outcome.new(table: (refusal ? nil : after) || @waiting_tables.find(table.id) || table.with(status: "closed"), refusal:)
    end

    # The vært's change to `seat`; the block returns [bord after, refusal].
    # A practice bord keeps its three bots.
    def host_changes_seat(table, user, seat, &)
      waiting_change(table) do |current|
        refusal = host_refusal(current, user)
        refusal ||= :practice_seats if current.practice?
        refusal ||= :no_such_seat unless current.seat?(seat)
        refusal ? [ current, refusal ] : yield(current)
      end
    end

    def host_refusal(table, user) = (:not_host unless table.host_id == user.id)

    def seated_elsewhere?(user, table)
      elsewhere = user.current_table
      !elsewhere.nil? && elsewhere.id != table.id
    end

    # Why the table type cannot be chosen: it is not one a vært may choose
    # (:unknown_kind), or it is the password type without a password
    # (:password_missing), unless the bord keeps the one it has.
    def kind_refusal(kind, password, keeps_password:)
      return :unknown_kind unless Table::CHOOSABLE_KINDS.include?(kind)

      :password_missing if kind == "password" && password.blank? && !keeps_password
    end
  end
end
