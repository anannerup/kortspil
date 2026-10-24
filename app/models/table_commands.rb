# The table command interface: the use-case boundary for a bord. Commands
# come in (start a practice table, create a table, sit, the vært's kick,
# add and remove bot and settings, start, pass, play, choose the moon, a
# bot's turn, the next runde, play again, leave, connect) and an Outcome
# comes out, holding the messages for each human seat. Callers broadcast
# those (TableChannel.deliver); nothing here touches Action Cable. The lobby hears of changes to tables and seats from
# the models themselves (Table#refresh_lobby).
#
# A command the bord refuses (sitting at a second bord, a taken seat,
# starting with empty seats) is an expected outcome: the Outcome carries the
# refusal, a symbol the caller turns into a message (tables.refusals.* in
# the locale), and nothing changes.
#
# Each command loads the spil once as a LiveGame (rebuilt from the game and
# round rows, under a row lock on the game, with the bord's Table::Seating)
# and orchestrates over it: what is due, what to save, what to schedule and
# whom to tell. Each pass and play is saved before the messages are
# returned, so only stored state is ever broadcast.
#
# Time is the scheduler's job (TableScheduler by default): bots act after
# their delay through #bot_turn, and when a runde is complete the next one
# is dealt after RESULT_PAUSE through #next_runde, so the runde result can
# be shown. The spil ends when the engine's Game says it is over.
#
# The table chat (TableChat, in memory) is open to the humans seated at the
# bord, before and during a spil: #chat posts, #chat_history replays.
class TableCommands
  # A payload for the human in `seat` (user `user_id`).
  Message = Data.define(:seat, :user_id, :payload)
  Outcome = Data.define(:table, :messages, :refusal) do
    def initialize(table:, messages: [], refusal: nil) = super
    def refused? = !refusal.nil?
  end

  # Seconds the runde result is shown before the next runde is dealt.
  RESULT_PAUSE = 10

  def initialize(scheduler: TableScheduler, bot: Hjerterfri::Bot.new, shuffler: Random.new, random: Random.new, chat: TableChat.default)
    @chat = chat
    @scheduler = scheduler
    @bot = bot
    @shuffler = shuffler
    @random = random
  end

  # Creates a practice table with the rules the user chose, the user in
  # seat 0 and three bots, and deals the first runde, which locks the rules.
  # Refused while the user sits at another bord.
  def start_practice(user:, rules: Hjerterfri::Rules.standard)
    return Outcome.new(table: nil, refusal: :seated_elsewhere) if user.current_table

    live = Table.transaction do
      table = Table.create!(host: user, kind: :practice, status: :playing, rules: rules.to_h)
      table.seating.seat_practice!(user)
      LiveGame.start(table:, rules: table.engine_rules, shuffler: @shuffler)
    end
    runde_started(live)
  end

  # Creates a table of the type the user chose (Table::CHOOSABLE_KINDS; a
  # password table with its password) with their rules and the user as
  # vært in seat 0. Refused while the user sits at another bord.
  def create_table(user:, rules: Hjerterfri::Rules.standard, kind: "open", password: nil)
    refusal = kind_refusal(kind.to_s, password, keeps_password: false)
    refusal ||= :seated_elsewhere if user.current_table
    return Outcome.new(table: nil, refusal:) if refusal

    table = Table.transaction do
      Table.create!(host: user, kind:, password: password.presence, status: :waiting, rules: rules.to_h).tap { |created| created.seating.sit!(user, 0) }
    end
    Outcome.new(table:)
  end

  # The user takes the free seat `seat` at a table that has not started,
  # or moves there if they sit at it already. A password table needs its
  # password to sit down (see Seating#refusal_to_sit).
  def sit(table:, user:, seat:, password: nil)
    table.with_lock do
      seating = table.seating
      refusal = seating.refusal_to_sit(user, seat, password:)
      seating.sit!(user, seat) unless refusal
      Outcome.new(table:, refusal:)
    end
  end

  # The vært kicks the player in `seat` before the start. It is not a ban:
  # they may sit down again. Bots are removed with #remove_bot, and the vært
  # stands up instead of kicking themself.
  def kick(table:, user:, seat:)
    host_changes_seat(table, user, seat) do |seating|
      occupant = seating.occupants.fetch(seat)
      next :nobody_to_kick unless occupant.human? && occupant.user_id != user.id

      seating.empty!(seat)
      nil
    end
  end

  # The vært puts a bot in the empty seat `seat` before the start.
  def add_bot(table:, user:, seat:)
    host_changes_seat(table, user, seat) do |seating|
      refusal = seating.refusal_to_fill(seat)
      seating.seat_bot!(seat) unless refusal
      refusal
    end
  end

  # The vært takes the bot in `seat` out again before the start.
  def remove_bot(table:, user:, seat:)
    host_changes_seat(table, user, seat) do |seating|
      next :no_bot_there unless seating.occupants.fetch(seat).bot?

      seating.empty!(seat)
      nil
    end
  end

  # The vært changes the rules and the table type while the table waits.
  # A password table needs a password; left blank, it keeps the one it has.
  # Leaving the password type drops the password.
  def change_settings(table:, user:, rules:, kind:, password: nil)
    table.with_lock do
      refusal = host_refusal(table, user) || kind_refusal(kind.to_s, password, keeps_password: table.password?)
      table.update!(rules: rules.to_h, kind:, **(password.present? ? { password: } : {})) unless refusal
      Outcome.new(table:, refusal:)
    end
  end

  # The vært starts the spil once every seat is taken: the first runde is
  # dealt, which locks the rules, and every seat gets its state.
  def start(table:, user:)
    refusal, live = table.with_lock do
      refused = start_refusal(table, user)
      next [ refused, nil ] if refused

      table.playing!
      [ nil, LiveGame.start(table:, rules: table.engine_rules, shuffler: @shuffler) ]
    end
    return Outcome.new(table:, refusal:) if refusal

    runde_started(live)
  end

  # The user passes three cards. A rejected pass is answered to that seat only.
  def pass(table:, user:, cards:)
    seated(table, user) { |game, seat| act(game, seat) { Hjerterfri::Pass.new(cards:) } }
  end

  # The user plays a card. A rejected play is answered to that seat only.
  def play(table:, user:, card:)
    seated(table, user) { |game, seat| act(game, seat) { Hjerterfri::Play.new(card:) } }
  end

  # The moon shooter chooses under shooter's choice (Hjerterfri::MoonChoice).
  # A rejected choice is answered to that seat only.
  def choose_moon(table:, user:, option:)
    seated(table, user) { |game, seat| act(game, seat) { Hjerterfri::MoonChoice.new(option:) } }
  end

  # A bot's scheduled move. It is dropped when it is no longer due (see
  # LiveGame#bot_turn_due?), so a duplicate or stale job does nothing.
  def bot_turn(game_id:, seat:, version:)
    act(Game.find(game_id), seat) do |live|
      next unless live.bot_turn_due?(seat, version)

      view = live.engine_round.view_for(seat)
      if live.engine_round.passing?
        Hjerterfri::Pass.new(cards: @bot.choose_pass(view[:hand]))
      elsif live.engine_round.choosing_moon?
        Hjerterfri::MoonChoice.new(option: @bot.choose_moon(seat:, totals: live.engine_game.totals))
      else
        Hjerterfri::Play.new(card: @bot.choose_play(view))
      end
    end
  end

  # Deals runde `number` once the runde before it is complete and the spil
  # goes on. Scheduled after a runde ends; a repeat does nothing.
  def next_runde(game_id:, number:)
    game = Game.find(game_id)
    live = LiveGame.locked(game) { |current| current.deal_next(shuffler: @shuffler) if current.next_runde_number == number }
    return Outcome.new(table: game.table, messages: []) unless live

    runde_started(live)
  end

  # A seated user does not want to wait out the pause after a runde.
  def deal_next_runde(table:, user:)
    seated(table, user) { |game, _seat| next_runde(game_id: game.id, number: game.current_round.number + 1) }
  end

  # "Spil igen" once the current spil is finished: the user asks for
  # another (Game#ask_to_play_again!). When every human at the table has
  # asked, a new spil starts with the same seats and the table's rules; until
  # then every seat is told who has asked (state `play_again_seats`). At a
  # practice table the one human's ask starts it at once.
  def play_again(table:, user:)
    seated(table, user) do |_game, _seat|
      started, live = table.with_lock do
        current = table.current_game
        next unless current.finished? && table.playing?

        current.ask_to_play_again!(user)
        seating = table.seating
        next [ false, LiveGame.load(current) ] unless current.everyone_asked_to_play_again?(seating)

        [ true, LiveGame.start(table:, rules: table.engine_rules, shuffler: @shuffler) ]
      end
      next Outcome.new(table:, messages: []) unless live

      started ? runde_started(live) : Outcome.new(table:, messages: state_messages(live))
    end
  end

  # The user leaves the table. Before the start that is standing up (see
  # Seating#stand!). Once a spil has started, leaving forfeits a spil in
  # progress (see LiveGame#abandon!) and the table closes either way, which
  # also stops pending bot turns; every human seat is told. (At an open
  # table a bot is to take the seat instead: ticket 19.)
  def leave(table:, user:)
    return stand(table:, user:) if table.waiting?
    return leave_finished(table:, user:) if table.current_game&.finished?

    seated(table, user) do |game, _seat|
      seating = LiveGame.locked(game) do |live|
        live.abandon!(forfeited_by: user)
        table.closed!
        live.seating
      end
      messages = humans(seating).map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload: { "type" => "closed" }) }
      Outcome.new(table:, messages:)
    end
  end

  # A user (re)opens the table: they get the full state for their seat. If
  # bots are to act, their turns are scheduled again, in case a job was
  # lost; likewise the next runde after a completed one.
  def connect(table:, user:)
    seated(table, user) do |game, seat|
      live = LiveGame.load(game)
      schedule(live)
      Outcome.new(table:, messages: [ state_message(live, seat, user.id) ])
    end
  end

  # A seated user says something to the table. Every human seated there
  # gets the message; a refused one (blank, too long, too fast) is answered
  # to the author only. Nobody else may post.
  def chat(table:, user:, text:)
    seating = table.seating
    seat = seating.seat_of(user)
    return Outcome.new(table:) if seat.nil? || table.closed?

    posted = @chat.post(table.id, author: seating.occupants.fetch(seat), text:)
    if posted.refused?
      return Outcome.new(table:, messages: [ Message.new(seat:, user_id: user.id, payload: { "type" => "chat_rejected", "reason" => posted.refusal.to_s }) ])
    end

    payload = { "type" => "chat_message", "message" => posted.entry.as_json }
    Outcome.new(table:, messages: humans(seating).map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload:) })
  end

  # The table's recent chat for a seated user who (re)opens the table.
  def chat_history(table:, user:)
    seat = table.seating.seat_of(user)
    return Outcome.new(table:) if seat.nil? || table.closed?

    payload = { "type" => "chat_history", "messages" => @chat.messages(table.id).map(&:as_json), "max_length" => TableChat::MAX_LENGTH }
    Outcome.new(table:, messages: [ Message.new(seat:, user_id: user.id, payload:) ])
  end

  private

  def stand(table:, user:)
    table.with_lock { table.seating.stand!(user) if table.waiting? && table.seated?(user) }
    Outcome.new(table:)
  end

  # Leaving once the spil is finished loses nothing: the user stands up
  # and the table waits for players again, with the vært handed on if need
  # be (or closes when no humans are left). The others are sent back to
  # the waiting room.
  def leave_finished(table:, user:)
    seating = table.with_lock do
      next unless table.playing? && table.seated?(user)

      table.waiting!
      after = table.seating.stand!(user)
      after unless table.closed?
    end
    return Outcome.new(table:) unless seating

    Outcome.new(table:, messages: humans(seating).map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload: { "type" => "waiting" }) })
  end

  # Runs the vært's change to `seat` under the table's lock; the block
  # returns a refusal or nil.
  def host_changes_seat(table, user, seat)
    table.with_lock do
      seating = table.seating
      refusal = host_refusal(table, user)
      refusal ||= :no_such_seat unless seating.seat?(seat)
      refusal ||= yield(seating)
      Outcome.new(table:, refusal:)
    end
  end

  def host_refusal(table, user)
    return :not_waiting unless table.waiting?

    :not_host unless table.host_id == user.id
  end

  # Why the table type cannot be chosen: it is not one a vært may choose
  # (:unknown_kind), or it is the password type without a password
  # (:password_missing), unless the table keeps the one it has.
  def kind_refusal(kind, password, keeps_password:)
    return :unknown_kind unless Table::CHOOSABLE_KINDS.include?(kind)

    :password_missing if kind == "password" && password.blank? && !keeps_password
  end

  def start_refusal(table, user)
    refusal = host_refusal(table, user)
    return refusal if refusal

    :seats_not_filled unless table.seating.full?
  end

  # Yields the current game and the user's seat. A user who does not sit at
  # the table, or any user once it is closed, gets no messages.
  def seated(table, user)
    seat = table.seating.seat_of(user)
    game = table.current_game
    return Outcome.new(table:, messages: []) if seat.nil? || game.nil? || table.closed?

    yield game, seat
  end

  # Loads the spil under its lock, applies the intent the block returns
  # (nil: nothing to do) and saves the result before answering.
  def act(game, seat)
    intent, step = LiveGame.locked(game) do |live|
      next unless live.in_progress?

      chosen = yield(live)
      [ chosen, chosen && live.apply(seat, chosen) ]
    end
    return Outcome.new(table: game.table, messages: []) unless step
    return Outcome.new(table: game.table, messages: [ rejection_message(step.live, seat, intent, step.reason) ]) if step.rejected?

    # Bots' passes were scheduled when the runde was dealt.
    schedule(step.live) unless step.live.engine_round.passing?
    Outcome.new(table: game.table, messages: state_messages(step.live))
  end

  def runde_started(live)
    schedule(live)
    Outcome.new(table: live.game.table, messages: state_messages(live))
  end

  # The bots that are to act, and the next runde once this one is complete.
  def schedule(live)
    live.bots_to_act.each do |seat|
      @scheduler.bot_turn(game_id: live.game.id, seat:, version: live.version, delay: @bot.delay(random: @random))
    end
    number = live.next_runde_number
    @scheduler.next_runde(game_id: live.game.id, number:, delay: RESULT_PAUSE) if number
  end

  def humans(seating) = seating.occupants.select(&:human?)

  def state_messages(live)
    humans(live.seating).map { |human| state_message(live, human.seat, human.user_id) }
  end

  def state_message(live, seat, user_id)
    Message.new(seat:, user_id:, payload: { type: "state", state: live.state_for(seat) }.as_json)
  end

  def rejection_message(live, seat, intent, reason)
    payload = { type: "rejected", reason:, **intent.to_h }
    Message.new(seat:, user_id: live.seating.occupants.fetch(seat).user_id, payload: payload.as_json)
  end
end
