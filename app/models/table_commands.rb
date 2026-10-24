# The table command interface: the use-case boundary for a bord. Commands
# come in (start a practice table, create an open table, sit, start, pass,
# play, choose the moon, a bot's turn, the next runde, play again, leave,
# connect, heartbeat, disconnect, a clock tick) and an Outcome comes out, holding the messages for each human
# seat. Callers broadcast those (TableChannel.deliver); nothing here
# touches Action Cable. The lobby hears of changes to tables and seats from
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
# Absence (tickets 18 and 19, PLAN.md "Absence and leaving"): at an open
# bord, clients send heartbeats; a seat whose connection closes or whose
# heartbeats stop is frakoblet, and one that stays away for 60 seconds, or
# does not act for 60 seconds on its turn (warned at 30), has forladt: a
# bot takes the seat (Seating#take_over!) and the spil goes on. The clock is
# TurnClock; the time comes from the injected `clock` (#now), and #tick,
# which the scheduler runs when something is next due, applies it. Leaving
# with "Forlad bordet" forlader at once. When the last human forlader, the
# spil is afbrudt and the bord closes. Practice tables have no clock.
class TableCommands
  # A payload for the human in `seat` (user `user_id`).
  Message = Data.define(:seat, :user_id, :payload)
  Outcome = Data.define(:table, :messages, :refusal) do
    def initialize(table:, messages: [], refusal: nil) = super
    def refused? = !refusal.nil?
  end

  # Seconds the runde result is shown before the next runde is dealt.
  RESULT_PAUSE = 10

  def initialize(scheduler: TableScheduler, bot: Hjerterfri::Bot.new, shuffler: Random.new, random: Random.new, clock: Time)
    @scheduler = scheduler
    @bot = bot
    @shuffler = shuffler
    @random = random
    @clock = clock
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

  # Creates an open table in the lobby with the rules the user chose and
  # the user as vært in seat 0. Refused while the user sits at another bord.
  def create_table(user:, rules: Hjerterfri::Rules.standard)
    return Outcome.new(table: nil, refusal: :seated_elsewhere) if user.current_table

    table = Table.transaction do
      Table.create!(host: user, kind: :open, status: :waiting, rules: rules.to_h).tap { |created| created.seating.sit!(user, 0) }
    end
    Outcome.new(table:)
  end

  # The user takes the free seat `seat` at a table that has not started,
  # or moves there if they sit at it already (see Seating#refusal_to_sit).
  def sit(table:, user:, seat:)
    table.with_lock do
      seating = table.seating
      refusal = seating.refusal_to_sit(user, seat)
      seating.sit!(user, seat) unless refusal
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
      table.seating.heard_from_all!(at: now)
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

  # "Spil igen": a new spil at the same table with the same seats and the
  # table's rules, once the current one is finished.
  def play_again(table:, user:)
    seated(table, user) do |_game, _seat|
      live = table.with_lock do
        current = table.current_game
        next unless current.finished? && table.playing?

        LiveGame.start(table:, rules: table.engine_rules, shuffler: @shuffler)
      end
      live ? runde_started(live) : Outcome.new(table:, messages: [])
    end
  end

  # The user leaves the table ("Forlad bordet"). Before the start, or once
  # the spil is over, that is standing up (#stand). During a spil in
  # progress they forlader it (#forlade): a bot takes their seat at once
  # and the spil goes on, or, if they were the last human, it is afbrudt.
  def leave(table:, user:)
    return stand(table:, user:) if table.waiting?

    seated(table, user) do |game, seat|
      game.in_progress? ? forlade(game, seat) : stand_after_spil(table, user)
    end
  end

  # A user (re)opens the table: they get the full state for their seat. If
  # they were frakoblet, they are back in time and everyone is told. If
  # bots are to act, their turns are scheduled again, in case a job was
  # lost; likewise the next runde after a completed one, and the clock.
  def connect(table:, user:)
    seated(table, user) do |game, seat|
      back = table.seating.occupants.fetch(seat).frakoblet?
      back ? table.seating.connected!(seat, at: now) : table.seating.heartbeat!(seat, at: now)
      live = LiveGame.load(game)
      schedule(live)
      Outcome.new(table:, messages: back ? state_messages(live) : [ state_message(live, seat, user.id) ])
    end
  end

  # The client's keep-alive. A seat the clock took for frakoblet while its
  # connection was open after all comes back with it.
  def heartbeat(table:, user:)
    seated(table, user) do |_game, seat|
      next connect(table:, user:) if table.seating.occupants.fetch(seat).frakoblet?

      table.seating.heartbeat!(seat, at: now)
      Outcome.new(table:)
    end
  end

  # The user's connection to the table closed. During a spil in progress
  # at an open bord they are frakoblet from now on, and the others are told.
  def disconnect(table:, user:)
    seated(table, user) do |game, seat|
      next Outcome.new(table:) unless table.open? && game.in_progress?

      table.seating.disconnected!(seat, at: now)
      live = LiveGame.load(game)
      schedule_tick(live)
      Outcome.new(table:, messages: state_messages(live).reject { |message| message.seat == seat })
    end
  end

  # The clock tick: applies what TurnClock says is due now. Seats whose
  # heartbeats stopped are frakoblet, players warned on their turn are told
  # (only them), and seats out of time forlader. Then the next tick is
  # scheduled. A tick that finds nothing due changes nothing.
  def tick(game_id:)
    game = Game.find(game_id)
    at = now
    live, warned, changed = LiveGame.locked(game) { |current| apply_clock(current, at) }
    return Outcome.new(table: game.table) unless live

    forladt = live.turn_clock.forladt(at).map { |seat| forlade(game, seat, due_at: at) }
    schedule_tick(LiveGame.load(game.reload))
    messages = [ *(changed ? state_messages(live) : []), *warned.map { |seat| warning_message(live, seat, at) }, *forladt.flat_map(&:messages) ]
    Outcome.new(table: game.table, messages:)
  end

  private

  def now = @clock.now

  def stand(table:, user:)
    table.with_lock { table.seating.stand!(user) if table.waiting? && table.seated?(user) }
    Outcome.new(table:)
  end

  # Standing up once the spil is over: no loss. The bord closes when no
  # human is left (a practice table, always); otherwise it waits for
  # players again, and the others are told to go to its waiting page.
  def stand_after_spil(table, user)
    seating = table.with_lock do
      after = table.seating.stand!(user)
      table.waiting! unless table.closed?
      after
    end
    others = humans(seating).map { |human| Message.new(seat: human.seat, user_id: human.user_id, payload: { "type" => "waiting" }) }
    Outcome.new(table:, messages: [ closed_message(user.id), *others ])
  end

  # The seat's player forlader the spil in progress: a bot takes over the
  # seat (and acts at once if it is to act), or, when they are the last
  # human, the spil is afbrudt and the bord closes. Passively (`due_at`, from
  # the clock) only if the seat is still out of time when it gets the lock.
  def forlade(game, seat, due_at: nil)
    leaver, live = LiveGame.locked(game) do |current|
      occupant = current.seating.occupants.fetch(seat)
      next unless current.in_progress? && occupant.human?
      next if due_at && current.turn_clock.forladt(due_at).exclude?(seat)

      [ occupant.user_id, hand_over(current, seat, occupant.user_id) ]
    end
    return Outcome.new(table: game.table) unless leaver

    return Outcome.new(table: game.table, messages: [ closed_message(leaver) ]) if live.nil?

    told = Message.new(seat:, user_id: leaver, payload: { "type" => "forladt" })
    after = live.bots_to_act.include?(seat) ? bot_turn(game_id: game.id, seat:, version: live.version) : runde_going_on(live)
    Outcome.new(table: game.table, messages: [ told, *after.messages ])
  end

  # Under the game's lock: the bot's LiveGame, or nil once the spil is afbrudt.
  def hand_over(live, seat, user_id)
    if humans(live.seating).none? { |human| human.seat != seat }
      live.abandon!(forfeited_by: User.find(user_id))
      live.game.table.closed!
      return nil
    end

    live.with_seating(live.seating.take_over!(seat, game: live.game, at_play: live.version))
  end

  def runde_going_on(live)
    schedule(live)
    Outcome.new(table: live.game.table, messages: state_messages(live))
  end

  # Under the game's lock: marks lost connections and warnings. Returns the
  # LiveGame after them, the seats warned, and whether anyone was lost.
  def apply_clock(live, at)
    return unless live.in_progress?

    clock = live.turn_clock
    lost = clock.lost(at)
    seating = live.seating
    lost.each { |seat, since| seating = seating.disconnected!(seat, at: since) }
    warned = clock.to_warn(at)
    warned.each { |seat| seating = seating.warned!(seat, at:) }
    [ live.with_seating(seating), warned, lost.any? ]
  end

  def start_refusal(table, user)
    return :not_waiting unless table.waiting?
    return :not_host unless table.host_id == user.id

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

    # Bots' passes were scheduled when the runde was dealt, and the clock
    # of the pass runs from the deal.
    unless step.live.engine_round.passing?
      step.live.turn_started!(at: now)
      schedule(step.live)
    end
    Outcome.new(table: game.table, messages: state_messages(step.live))
  end

  def runde_started(live)
    live.turn_started!(at: now)
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
    schedule_tick(live)
  end

  # Schedules a tick for when the clock next has something due, unless an
  # earlier one is already coming (games.tick_at), so one chain of ticks
  # runs per spil.
  def schedule_tick(live)
    at = live.turn_clock.next_check
    return unless at

    pending = live.game.reload.tick_at
    return if pending && pending > now && pending <= at

    live.game.update_columns(tick_at: at)
    @scheduler.tick(game_id: live.game.id, delay: [ at - now, 0 ].max.to_f)
  end

  def humans(seating) = seating.occupants.select(&:human?)

  def state_messages(live)
    humans(live.seating).map { |human| state_message(live, human.seat, human.user_id) }
  end

  def state_message(live, seat, user_id)
    Message.new(seat:, user_id:, payload: { type: "state", state: live.state_for(seat, now:) }.as_json)
  end

  def warning_message(live, seat, at)
    Message.new(seat:, user_id: live.seating.occupants.fetch(seat).user_id, payload: { type: "turn_warning", seconds_left: live.turn_clock.seconds_left(seat, at) }.as_json)
  end

  def closed_message(user_id) = Message.new(seat: nil, user_id:, payload: { "type" => "closed" })

  def rejection_message(live, seat, intent, reason)
    payload = { type: "rejected", reason:, **intent.to_h }
    Message.new(seat:, user_id: live.seating.occupants.fetch(seat).user_id, payload: payload.as_json)
  end
end
