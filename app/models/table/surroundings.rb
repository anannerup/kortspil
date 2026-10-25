class Table
  # What a bord's actions use from outside the bord, injected so that tests
  # are deterministic: the time (`clock`, #now), the shuffle of each deal
  # (`shuffler`), the bots' player (`bot`, built from `random`), what runs
  # later as jobs (`scheduler`: bot turns, the next runde and the tur-ur's
  # checks; TableScheduler), the table chat (`chat`, TableChat) and the
  # borde waiting for their spil (`waiting_tables`, WaitingTables).
  #
  # Every action takes it as `surroundings:`, defaulting to the real ones.
  # Tests pass a FakeClock and a FakeScheduler.
  Surroundings = Data.define(:clock, :shuffler, :bot, :scheduler, :chat, :waiting_tables) do
    # Every bot plays Mellem until the level is chosen per seat (ticket 22).
    def initialize(clock: Time, shuffler: Random.new, random: Random.new, bot: Hjerterfri::Bot.new(level: :mellem, random:),
                   scheduler: TableScheduler, chat: TableChat.default, waiting_tables: WaitingTables.default)
      super(clock:, shuffler:, bot:, scheduler:, chat:, waiting_tables:)
    end

    def now = clock.now
  end
end
