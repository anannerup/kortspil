# The table command interface: the use-case boundary for a bord. Commands
# come in (start a practice table, pass, play, a bot's turn, the next runde,
# play again, leave, connect) and an Outcome comes out, holding the messages
# for each human seat. Callers broadcast those (TableChannel.deliver);
# nothing here touches Action Cable.
#
# State is rebuilt from the game and round rows for every command, and each
# pass and play is saved before the messages are returned, so only stored
# state is ever broadcast. Commands for one spil are serialized by a row
# lock on the game.
#
# Time is the scheduler's job (TableScheduler by default): bots act after
# their delay through #bot_turn, and when a runde is complete the next one
# is dealt after RESULT_PAUSE through #next_runde, so the runde result can
# be shown. The spil ends when the engine's Game says it is over.
class TableCommands
  # A payload for the human in `seat` (user `user_id`).
  Message = Data.define(:seat, :user_id, :payload)
  Outcome = Data.define(:table, :messages)

  BOT_NAMES = [ "Bot 1", "Bot 2", "Bot 3" ].freeze
  SEAT_COUNT = Hjerterfri::Deal::SEAT_COUNT
  # Versions per runde: four passes, 52 plays, and one step for the deal,
  # so the first state of a runde is newer than the last of the one before.
  STEPS_PER_RUNDE = SEAT_COUNT + (SEAT_COUNT * Hjerterfri::Deal::HAND_SIZE) + 1
  # Seconds the runde result is shown before the next runde is dealt.
  RESULT_PAUSE = 10

  def initialize(scheduler: TableScheduler, bot: Hjerterfri::Bot.new, shuffler: Random.new, random: Random.new)
    @scheduler = scheduler
    @bot = bot
    @shuffler = shuffler
    @random = random
  end

  # Creates a practice table with the user in seat 0 and three bots, and
  # deals the first runde.
  def start_practice(user:, rules: Hjerterfri::Rules.standard)
    game = Table.transaction do
      table = Table.create!(host: user, kind: :practice, status: :playing)
      seats = [ Game.human_seat(user), *BOT_NAMES.map { |name| Game.bot_seat(name) } ]
      table.games.create!(rules: rules.to_h, seats:).tap { |created| deal_runde(created, 1) }
    end
    runde_started(game)
  end

  # The user passes three cards. A rejected pass is answered to that seat only.
  def pass(table:, user:, cards:)
    seated(table, user) { |game, seat| act(game, seat) { Hjerterfri::Pass.new(cards:) } }
  end

  # The user plays a card. A rejected play is answered to that seat only.
  def play(table:, user:, card:)
    seated(table, user) { |game, seat| act(game, seat) { Hjerterfri::Play.new(card:) } }
  end

  # A bot's scheduled move. It is dropped when the state has moved on since
  # it was scheduled (`version`), so a duplicate or stale job does nothing.
  # Bots pass at the same time, so a pass only needs the runde to be the
  # one it was scheduled in and the bot not to have passed yet.
  def bot_turn(game_id:, seat:, version:)
    game = Game.find(game_id)
    act(game, seat) do |round, record|
      next unless game.bot?(seat)

      case round.phase
      when :passing
        next if round.passes.passed?(seat) || version < runde_base(record)

        Hjerterfri::Pass.new(cards: @bot.choose_pass(round.view_for(seat)[:hand]))
      when :playing
        next unless round.to_act == seat && version(record) == version

        Hjerterfri::Play.new(card: @bot.choose_play(round.view_for(seat)))
      end
    end
  end

  # Deals runde `number` once the runde before it is complete and the spil
  # goes on. Scheduled after a runde ends; a repeat does nothing.
  def next_runde(game_id:, number:)
    game = Game.find(game_id)
    dealt = game.with_lock do
      last = game.rounds.reload.last
      next false unless game.in_progress? && last.number == number - 1 && last.to_engine(game.engine_rules).complete?

      deal_runde(game, number)
    end
    return Outcome.new(table: game.table, messages: []) unless dealt

    runde_started(game)
  end

  # A seated user does not want to wait out the pause after a runde.
  def deal_next_runde(table:, user:)
    seated(table, user) { |game, _seat| next_runde(game_id: game.id, number: game.current_round.number + 1) }
  end

  # "Spil igen": a new spil at the same table with the same seats and rules,
  # once the current one is finished.
  def play_again(table:, user:)
    seated(table, user) do |_game, _seat|
      game = table.with_lock do
        current = table.current_game
        next unless current.finished? && table.playing?

        table.games.create!(rules: current.rules, seats: current.seats).tap { |created| deal_runde(created, 1) }
      end
      game ? runde_started(game) : Outcome.new(table:, messages: [])
    end
  end

  # The user leaves the table. Leaving a spil in progress forfeits it: the
  # spil is abandoned with the totals of its completed runder and the leaver
  # recorded, so it counts as a loss. The practice table closes either way,
  # which also stops pending bot turns; every human seat is told.
  def leave(table:, user:)
    seated(table, user) do |game, _seat|
      game.with_lock do
        game.update!(status: :abandoned, final_scores: game.engine_game.totals, forfeited_by: user) if game.in_progress?
        table.closed!
      end
      messages = game.human_seats.map { |seat, user_id| Message.new(seat:, user_id:, payload: { "type" => "closed" }) }
      Outcome.new(table:, messages:)
    end
  end

  # A user (re)opens the table: they get the full state for their seat. If
  # bots are to act, their turns are scheduled again, in case a job was
  # lost; likewise the next runde after a completed one.
  def connect(table:, user:)
    seated(table, user) do |game, seat|
      record = game.current_round
      round = record.to_engine(game.engine_rules)
      schedule_runde(game, record, round)
      schedule_next_runde(game, record, round)
      Outcome.new(table:, messages: [ state_message(game, record, round, seat) ])
    end
  end

  private

  # Yields the current game and the user's seat. A user who does not sit at
  # the table, or any user once it is closed, gets no messages.
  def seated(table, user)
    game = table.current_game
    seat = game&.seat_of(user)
    return Outcome.new(table:, messages: []) if seat.nil? || table.closed?

    yield game, seat
  end

  # Loads the runde under the game's lock, applies the intent the block
  # returns (nil: nothing to do) and saves the result before answering.
  def act(game, seat)
    record = intent = result = nil
    game.with_lock do
      next unless game.in_progress?

      record = game.rounds.reload.last
      round = record.to_engine(game.engine_rules)
      intent = yield(round, record)
      next unless intent

      result = round.apply(seat, intent)
      save_step(game, record, result.round) if result.accepted?
    end
    return Outcome.new(table: game.table, messages: []) unless result
    return Outcome.new(table: game.table, messages: [ rejection_message(game, seat, intent, result.reason) ]) if result.rejected?

    schedule_after_step(game, record, result.round)
    Outcome.new(table: game.table, messages: state_messages(game, record, result.round))
  end

  # Stores the pass or play; the runde that completes the spil finishes it.
  def save_step(game, record, round)
    record.update!(passes: round.passes_string, plays: round.plays_string)
    return unless round.complete?

    spil = game.engine_game
    game.update!(status: :finished, final_scores: spil.totals) if spil.over?
  end

  def deal_runde(game, number)
    deal = Hjerterfri::Deal.shuffled(shuffler: @shuffler)
    game.rounds.create!(number:, pass_direction: Hjerterfri::PassDirection.for_runde(number).to_s, deal: deal.to_s)
  end

  def runde_started(game)
    record = game.rounds.reload.last
    round = record.to_engine(game.engine_rules)
    schedule_runde(game, record, round)
    Outcome.new(table: game.table, messages: state_messages(game, record, round))
  end

  # After a pass or play: the bot to play next, or the next runde. Bots'
  # passes were scheduled when the runde was dealt.
  def schedule_after_step(game, record, round)
    if round.complete?
      schedule_next_runde(game, record, round)
    elsif round.phase == :playing
      schedule_bot_play(game, record, round)
    end
  end

  # Every bot that has still to pass, or else the bot to play.
  def schedule_runde(game, record, round)
    return schedule_bot_play(game, record, round) unless round.phase == :passing

    (0...SEAT_COUNT).each do |seat|
      next if !game.bot?(seat) || round.passes.passed?(seat)

      @scheduler.bot_turn(game_id: game.id, seat:, version: version(record), delay: @bot.delay(random: @random))
    end
  end

  def schedule_bot_play(game, record, round)
    seat = round.to_act
    return if seat.nil? || !game.bot?(seat)

    @scheduler.bot_turn(game_id: game.id, seat:, version: version(record), delay: @bot.delay(random: @random))
  end

  def schedule_next_runde(game, record, round)
    return unless round.complete? && game.in_progress?

    @scheduler.next_runde(game_id: game.id, number: record.number + 1, delay: RESULT_PAUSE)
  end

  # Grows with every pass, play and deal in the spil, so clients can ignore
  # a state that arrives after a newer one.
  def version(record) = runde_base(record) + record.passes_made + record.plays_made
  def runde_base(record) = (record.number - 1) * STEPS_PER_RUNDE

  def state_messages(game, record, round)
    game.human_seats.map { |seat, user_id| state_message(game, record, round, seat, user_id:) }
  end

  def state_message(game, record, round, seat, user_id: game.human_seats.fetch(seat))
    payload = {
      type: "state",
      state: {
        table_id: game.table_id,
        game_id: game.id,
        status: game.status,
        round_number: record.number,
        version: version(record),
        seats: game.seat_names,
        view: round.view_for(seat),
        points_taken: round.points_taken,
        score: score(game.engine_game)
      }
    }
    Message.new(seat:, user_id:, payload: payload.as_json)
  end

  # The score sheet: completed runder with running totals, who leads (the
  # lowest total) and, once the spil is over, who won.
  def score(spil)
    totals = spil.totals
    leaders = spil.results.empty? ? [] : totals.each_index.select { |seat| totals[seat] == totals.min }
    { end_score: spil.rules.end_score, rows: spil.rows, totals:, leaders:, winners: spil.winners }
  end

  def rejection_message(game, seat, intent, reason)
    payload = { type: "rejected", reason:, **intent.to_h }
    Message.new(seat:, user_id: game.human_seats.fetch(seat), payload: payload.as_json)
  end
end
