module Esmakker
  # One entry of a runde's action log: what a seat did, as a short token
  # (later tickets: a melding, pas, "det kan jeg selv", trump, the called
  # ace, discards, fordækt, banks, plays). The log is append-only and
  # stored as space-separated "seat:token" entries, e.g. "1:pas 2:9"; the
  # runde is rebuilt by replaying it (Round.from_strings).
  class Action < Data.define(:seat, :token)
    FORMAT = /\A[0-3]:[^\s:]+\z/

    def self.parse_log(string) = string.to_s.split.map { |entry| parse(entry) }

    def self.parse(entry)
      raise ArgumentError, "not an action: #{entry.inspect}" unless entry.is_a?(String) && entry.match?(FORMAT)

      seat, token = entry.split(":")
      new(seat: seat.to_i, token:)
    end

    def self.log_string(actions) = actions.map(&:to_s).join(" ")

    def to_s = "#{seat}:#{token}"
  end
end
