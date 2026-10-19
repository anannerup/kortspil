# The table command interface: the use-case boundary for a bord. Commands
# come in (start a practice table, play a card, a bot's turn, connect) and
# an Outcome comes out, holding the messages for each human seat. Callers
# broadcast those (TableChannel.deliver); nothing here touches Action Cable.
#
# State is rebuilt from the game and round rows for every command, and each
# play is saved before the messages are returned, so only stored state is
# ever broadcast. Commands for one spil are serialized by a row lock on the
# game. Bots act through the same path: when a bot is to act, the scheduler
# is asked to run #bot_turn after the bot's delay.
#
# This ticket plays one runde without passing; passing, further runder and
# the turn clock are added by later tickets.
class TableCommands
  # A payload for the human in `seat` (user `user_id`).
  Message = Data.define(:seat, :user_id, :payload)
  Outcome = Data.define(:table, :messages)

  BOT_NAMES = [ "Bot 1", "Bot 2", "Bot 3" ].freeze
  # Passing arrives in ticket 07; until then every runde is played as dealt.
  NO_PASS = "none".freeze
  CARDS_PER_RUNDE = Hjerterfri::Deal::SEAT_COUNT * Hjerterfri::Deal::HAND_SIZE

  def initialize(scheduler: BotTurnJob, bot: Hjerterfri::Bot.new, shuffler: Random.new, random: Random.new)
    @scheduler = scheduler
    @bot = bot
    @shuffler = shuffler
    @random = random
  end

  # Creates a practice table with the user in seat 0 and three bots, and
  # deals the first runde.
  def start_practice(user:)
    deal = Hjerterfri::Deal.shuffled(shuffler: @shuffler)
    game = Table.transaction do
      table = Table.create!(host: user, kind: :practice, status: :playing)
      seats = [ Game.human_seat(user), *BOT_NAMES.map { |name| Game.bot_seat(name) } ]
      table.games.create!(rules: Hjerterfri::Rules.standard.to_h, seats:).tap do |created|
        created.rounds.create!(number: 1, pass_direction: NO_PASS, deal: deal.to_s)
      end
    end
    record = game.current_round
    round = engine_round(game, record)
    schedule_bot_turn(game, record, round)
    Outcome.new(table: game.table, messages: state_messages(game, record, round))
  end

  # The user plays a card. A rejected play is answered to that seat only.
  def play(table:, user:, card:)
    game = table.current_game
    seat = game&.seat_of(user)
    return Outcome.new(table:, messages: []) if seat.nil?

    act(game, seat) { Hjerterfri::Play.new(card:) }
  end

  # A bot's scheduled move. It is dropped when the state has moved on since
  # it was scheduled (`version`), so a duplicate or stale job does nothing.
  def bot_turn(game_id:, seat:, version:)
    game = Game.find(game_id)
    act(game, seat) do |round, record|
      next unless game.bot?(seat) && round.to_act == seat && version(record) == version

      Hjerterfri::Play.new(card: @bot.choose_play(round.view_for(seat)))
    end
  end

  # A user (re)opens the table: they get the full state for their seat. If a
  # bot is to act, its turn is scheduled again, in case the job was lost.
  def connect(table:, user:)
    game = table.current_game
    seat = game&.seat_of(user)
    return Outcome.new(table:, messages: []) if seat.nil?

    record = game.current_round
    round = engine_round(game, record)
    schedule_bot_turn(game, record, round)
    Outcome.new(table:, messages: [ state_message(game, record, round, seat) ])
  end

  private

  # Loads the runde under the game's lock, applies the intent the block
  # returns (nil: nothing to do) and saves the result before answering.
  def act(game, seat)
    record = intent = result = nil
    game.with_lock do
      record = game.rounds.reload.last
      round = engine_round(game, record)
      intent = yield(round, record)
      next unless intent

      result = round.apply(seat, intent)
      record_play(game, record, result.round) if result.accepted?
    end
    return Outcome.new(table: game.table, messages: []) unless result
    return Outcome.new(table: game.table, messages: [ rejection_message(game, seat, intent, result.reason) ]) if result.rejected?

    schedule_bot_turn(game, record, result.round)
    Outcome.new(table: game.table, messages: state_messages(game, record, result.round))
  end

  def record_play(game, record, round)
    record.update!(plays: round.plays_string)
    return unless round.complete?

    # One runde is the whole spil until ticket 08 adds further runder.
    game.finished!
    game.table.closed!
  end

  def engine_round(game, record)
    Hjerterfri::Round.from_strings(rules: game.engine_rules, deal: record.deal, plays: record.plays)
  end

  def schedule_bot_turn(game, record, round)
    seat = round.to_act
    return if seat.nil? || !game.bot?(seat)

    @scheduler.schedule(game_id: game.id, seat:, version: version(record), delay: @bot.delay(random: @random))
  end

  # Grows with every play in the spil, so clients can ignore a state that
  # arrives after a newer one.
  def version(record) = ((record.number - 1) * CARDS_PER_RUNDE) + record.plays_made

  def state_messages(game, record, round)
    game.human_seats.map { |seat, user_id| state_message(game, record, round, seat, user_id:) }
  end

  def state_message(game, record, round, seat, user_id: game.human_seats.fetch(seat))
    payload = {
      type: "state",
      state: {
        table_id: game.table_id,
        game_id: game.id,
        round_number: record.number,
        version: version(record),
        seats: game.seat_names,
        view: round.view_for(seat)
      }
    }
    Message.new(seat:, user_id:, payload: payload.as_json)
  end

  def rejection_message(game, seat, intent, reason)
    payload = { type: "rejected", reason:, card: intent.card }
    Message.new(seat:, user_id: game.human_seats.fetch(seat), payload: payload.as_json)
  end
end
