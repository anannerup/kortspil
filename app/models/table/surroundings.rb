class Table
  # What a bord's actions use from outside the bord, injected so that tests
  # are deterministic: the time (`clock`, #now), the shuffle of each deal
  # (`shuffler`), the lots the bots draw (`random`, for #strategy), what
  # runs later as jobs (`scheduler`: bot turns, the next runde and the
  # tur-ur's checks; TableScheduler), the table chat (`chat`, TableChat) and
  # the borde waiting for their spil (`waiting_tables`, WaitingTables).
  #
  # Every action takes it as `surroundings:`, defaulting to the real ones.
  # Tests pass a FakeClock and a FakeScheduler.
  Surroundings = Data.define(:clock, :shuffler, :random, :scheduler, :chat, :waiting_tables) do
    def initialize(clock: Time, shuffler: Random.new, random: Random.new,
                   scheduler: TableScheduler, chat: TableChat.default, waiting_tables: WaitingTables.default)
      super
    end

    def now = clock.now

    # The strategy a bot player chooses with at `level`: Hjerterfri::Bot,
    # drawing its lots from `random`.
    def strategy(level) = Hjerterfri::Bot.new(level:, random:)
  end
end
