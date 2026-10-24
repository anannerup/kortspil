# The table command interface: the use-case boundary for a bord. Commands
# come in (start a practice table, create an open table, sit, start, pass,
# play, choose the moon, a bot's turn, the next runde, play again, leave,
# connect) and an Outcome comes out, holding the messages for each human
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
class TableCommands
  # A payload for the human in `seat` (user `user_id`).
  Message = Data.define(:seat, :user_id, :payload)
  Outcome = Data.define(:table, :messages, :refusal) do
    def initialize(table:, messages: [], refusal: nil) = super
    def refused? = !refusal.nil?
  end

  # Seconds the runde result is shown before the next runde is dealt.
  RESULT_PAUSE = 10

  def initialize(scheduler: TableScheduler, bot: Hjerterfri::Bot.new, shuffler: Random.new, random: Random.new)
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

  # The user leaves the table. Before the start that is standing up (see
  # Seating#stand!). Once a spil has started, leaving forfeits a spil in
  # progress (see LiveGame#abandon!) and the table closes either way, which
  # also stops pending bot turns; every human seat is told. (At an open
  # table a bot is to take the seat instead: ticket 19.)
  def leave(table:, user:)
    return stand(table:, user:) if table.waiting?

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

  private

  def stand(table:, user:)
    table.with_lock { table.seating.stand!(user) if table.waiting? && table.seated?(user) }
    Outcome.new(table:)
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
