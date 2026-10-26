class WaitingTable
  # The actions at a bord before its spil: making a bord or a practice
  # bord, sitting, leaving (standing up), the vært's kick, bots, settings
  # and pufs, a friend's answer to a puf, and "Start spil", which stores the
  # bord, its seats and the spil in one transaction (Table.store!). Nothing
  # here writes to the database before the start.
  #
  # Each action runs under the registry's lock (WaitingTables#change),
  # first letting pufs whose time is up expire (the injected clock), and
  # returns a Table::Outcome whose table is the bord as it is after the
  # action. The bord decides: an action it does not allow is refused with
  # a reason and changes nothing; one at a bord that has started or closed
  # is refused (:not_waiting).
  module Actions
    extend ActiveSupport::Concern

    class_methods do
      # Makes a practice bord for `game` (GAMES; hjerterfri unless chosen)
      # with the user in seat 0 and three bots, so husets regler (of the
      # rules the user chose, the game's GameRules or its rules form, only
      # how long the spil lasts counts; WaitingTable#initialize). An es-makker practice bord
      # plays TableRules::STANDARD_RUNDER runder until the user changes it.
      # Like any bord it waits for its start: the user may change the rules
      # first. Refused while the user sits at another bord.
      def set_up_practice(user:, rules: nil, game: "hjerterfri", surroundings: Table::Surroundings.new)
        return Table::Outcome.new(table: nil, refusal: :game_not_available) unless GAMES.include?(game.to_s)

        game_rules = GameRules.cast(rules || {}, game:)
        refusal = GameRules.invalid(game) unless game_rules
        refusal ||= :seated_elsewhere if user.current_table
        return Table::Outcome.new(table: nil, refusal:) if refusal

        rules = Rules.new(table: TableRules.standard(kind: "practice", game:), game: game_rules)
        Table::Outcome.new(table: surroundings.waiting_tables.add(build(host: user, rules:, game: game.to_s)))
      end

      # Makes a bord for `game` (chosen in the lobby; GAMES) of the type the
      # user chose (TableRules::CHOOSABLE_KINDS; a password table with its
      # password) with their rules (the game's GameRules, or its rules form;
      # the standard ones when none) and the user as vært in seat 0. An
      # es-makker bord plays TableRules::STANDARD_RUNDER runder until the
      # vært changes it. Refused while the user sits at another bord.
      def set_up(user:, rules: nil, kind: "open", password: nil, game: "hjerterfri", surroundings: Table::Surroundings.new)
        return Table::Outcome.new(table: nil, refusal: :game_not_available) unless GAMES.include?(game.to_s)

        game_rules = GameRules.cast(rules || {}, game:)
        table_rules = TableRules.standard(kind:, game:)
        refusal = GameRules.invalid(game) unless game_rules
        refusal ||= table_rules.refusal(password, keeps_password: false)
        refusal ||= :seated_elsewhere if user.current_table
        return Table::Outcome.new(table: nil, refusal:) if refusal

        rules = Rules.new(table: table_rules, game: game_rules)
        Table::Outcome.new(table: surroundings.waiting_tables.add(build(host: user, rules:, password:, game: game.to_s)))
      end
    end

    # The user takes the free seat `seat`, or moves there if they sit at the
    # bord already (see #refusal_to_sit). One bord per user.
    def sit(user:, seat:, password: nil, surroundings: Table::Surroundings.new)
      change(surroundings) do |current|
        refusal = :seated_elsewhere if seated_elsewhere?(user, current)
        refusal ||= current.refusal_to_sit(user, seat, password:)
        refusal ? [ current, refusal ] : [ current.with_seated(user, seat), nil ]
      end
    end

    # The user stands up and goes back to the lobby. The bord closes when no
    # human is left (a practice bord, always), and its chat goes with it.
    def leave(user:, surroundings: Table::Surroundings.new)
      change(surroundings) do |current|
        after = current.without(user.id)
        next [ after, nil ] if after.humans.any?

        surroundings.chat.forget(current.id)
        [ nil, nil ]
      end
    end

    # The vært kicks the player in `seat`. It is not a ban: they may sit
    # down again. Bots are removed with #remove_bot, and the vært stands up
    # instead of kicking themself.
    def kick(user:, seat:, surroundings: Table::Surroundings.new)
      host_changes_seat(user, seat, surroundings) do |current|
        occupant = current.occupants.fetch(seat)
        next [ current, :nobody_to_kick ] unless occupant.human? && occupant.user_id != user.id

        [ current.emptied(seat), nil ]
      end
    end

    # The vært puts a bot in the empty seat `seat`, at the level they chose
    # (Let, Mellem or Svær; Mellem unless they chose).
    def add_bot(user:, seat:, level: Table::Seating::BOT_LEVEL, surroundings: Table::Surroundings.new)
      bot_level = Table::Seating.bot_level(level)
      host_changes_seat(user, seat, surroundings) do |current|
        bot_level ? current.with_bot(seat, level: bot_level) : [ current, :unknown_bot_level ]
      end
    end

    # The vært changes the level of the bot in `seat` until the start, and
    # between spil at the waiting bord the players move to; at a practice
    # bord too, where the human is the vært of its three bots.
    def change_bot_level(user:, seat:, level:, surroundings: Table::Surroundings.new)
      bot_level = Table::Seating.bot_level(level)
      change(surroundings) do |current|
        refusal = host_refusal(current, user) || (:unknown_bot_level unless bot_level)
        refusal ? [ current, refusal ] : current.with_bot_level(seat, bot_level)
      end
    end

    # The vært takes the bot in `seat` out again.
    def remove_bot(user:, seat:, surroundings: Table::Surroundings.new)
      host_changes_seat(user, seat, surroundings) do |current|
        next [ current, :no_bot_there ] unless current.occupants.fetch(seat).bot?

        [ current.emptied(seat), nil ]
      end
    end

    # The vært changes the rules: the card game's (GameRules, or the rules
    # form) and the bord's own (TableRules: the table type, and at
    # es-makker the number of runder). A password table needs a password;
    # left blank, it keeps the one it has. Leaving the password type drops
    # the password. A practice bord stays one: only its game rules change,
    # whatever `kind` says. The game is not a setting. While a bot sits at
    # the bord, the card game's rules stay husets regler, whatever the form
    # says (WaitingTable#initialize); only how long the spil lasts changes.
    def change_settings(user:, rules:, kind: nil, password: nil, runder: nil, surroundings: Table::Surroundings.new)
      game_rules = GameRules.cast(rules, game:)
      table_rules = TableRules.cast(kind:, runder:, game:)
      change(surroundings) do |current|
        refusal = GameRules.invalid(game) unless game_rules
        refusal ||= :invalid_runder unless table_rules
        refusal ||= host_refusal(current, user)
        refusal ||= table_rules.refusal(password, keeps_password: current.password?) unless current.practice?
        next [ current, refusal ] if refusal

        [ current.with_settings(rules: Rules.new(table: table_rules, game: game_rules), password:), nil ]
      end
    end

    # A seated player nudges their `friend` to the bord (#with_nudge for
    # the cap). Only friends, only from a seat at the bord, not at a
    # practice bord.
    def nudge(user:, friend:, surroundings: Table::Surroundings.new)
      change(surroundings) do |current|
        refusal = :not_seated unless current.seated?(user)
        refusal ||= :practice_seats if current.practice?
        refusal ||= :not_friend unless friend && user.friends.exists?(friend.id)
        refusal ? [ current, refusal ] : current.with_nudge(friend, from: user, now: surroundings.now)
      end
    end

    # The one who sent a pending puf, or the vært, withdraws it, which
    # frees its seat.
    def withdraw_nudge(user:, nudge_id:, surroundings: Table::Surroundings.new)
      change(surroundings) { |current| current.with_withdrawn(nudge_id, user) }
    end

    # The nudged friend accepts (and is seated in a free seat, without the
    # password) or declines. Accepting is refused while they sit at another
    # bord; the puf stays pending.
    def answer_nudge(user:, nudge_id:, accept:, surroundings: Table::Surroundings.new)
      change(surroundings) do |current|
        next [ current, :seated_elsewhere ] if accept && seated_elsewhere?(user, current)

        current.with_answer(nudge_id, user, accept:)
      end
    end

    # Lets pufs whose time is up expire, so everyone sees it; the bord's
    # page asks when the next one is due.
    def expire_nudges(surroundings: Table::Surroundings.new)
      change(surroundings) { |current| [ current, nil ] }
    end

    # "Start spil": the vært starts the spil once every seat is taken
    # (WaitingTable#refusal_to_start). The
    # bord, its seat rows and the spil are stored in one transaction, the
    # first runde is dealt, and every seat gets its state. Pending pufs end
    # with it. The table chat comes along. The Outcome's table is the
    # stored table.
    def start(user:, surroundings: Table::Surroundings.new)
      stored = nil
      outcome = change(surroundings) do |current|
        refusal = host_refusal(current, user) || current.refusal_to_start
        next [ current, refusal ] if refusal

        stored = store(current, surroundings)
        [ nil, nil ]
      end
      return outcome if outcome.refused?

      stored.runde_started(stored.current_game, surroundings)
    end

    # Before the start there is no spil: its actions do nothing yet.
    %i[ act deal_next_runde connect heartbeat disconnect switch_vis_kort ].each do |action|
      define_method(action) { |**| Table::Outcome.new(table: self) }
    end

    def client_intent(_action, _data) = nil

    private

    # Under the registry's lock: the stored table with its seats and the
    # spil's first runde. The chat moves over, and the registry remembers
    # which table the bord became.
    def store(waiting, surroundings)
      stored = Table.store!(waiting, at: surroundings.now, shuffler: surroundings.shuffler)
      surroundings.chat.move(waiting.id, stored.id)
      surroundings.waiting_tables.started!(waiting.id, stored.id)
      stored
    end

    # Runs a change to the bord as it is now, under the registry's lock,
    # with pufs whose time is up expired. The block returns [bord after,
    # refusal]; on a refusal the expiries still count.
    def change(surroundings)
      registry = surroundings.waiting_tables
      after = nil
      refusal = registry.change(id) do |current|
        next [ nil, :not_waiting ] unless current

        current = current.with_expired_nudges(surroundings.now)
        after, refused = yield(current)
        [ refused ? current : after, refused ]
      end
      Table::Outcome.new(table: (refusal ? nil : after) || registry.find(id) || with(status: "closed"), refusal:)
    end

    # The vært's change to `seat`; the block returns [bord after, refusal].
    # A practice bord keeps its three bots.
    def host_changes_seat(user, seat, surroundings, &)
      change(surroundings) do |current|
        refusal = host_refusal(current, user)
        refusal ||= :practice_seats if current.practice?
        refusal ||= :no_such_seat unless current.seat?(seat)
        refusal ? [ current, refusal ] : yield(current)
      end
    end

    def host_refusal(table, user) = (:not_host unless table.host?(user))

    def seated_elsewhere?(user, table)
      elsewhere = user.current_table
      !elsewhere.nil? && elsewhere.id != table.id
    end
  end
end
