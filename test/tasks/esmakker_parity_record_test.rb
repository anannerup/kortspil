require "test_helper"
require "zlib"
require Rails.root.join("tools/esmakker_ai/parity_record").to_s

# The recorder behind `bin/rails esmakker:parity` (the Python port's parity
# check): what it writes replays in the Ruby engine to the same result.
class EsmakkerParityRecordTest < ActiveSupport::TestCase
  test "records seeded spil that replay to the recorded result" do
    path = Rails.root.join("tmp/esmakker_parity_test.jsonl.gz").to_s
    runder = EsmakkerParity.record(path, spil: 5, seed: 7)
    lines = Zlib::GzipReader.open(path) { |gz| gz.each_line.map { |line| JSON.parse(line) } }

    assert_equal 5, lines.size
    assert_equal runder, lines.sum { |line| line["runder"].size }
    lines.each do |line|
      rules = Esmakker::Rules.from_h(line["rules"])
      line["runder"].each do |runde|
        round = Esmakker::Round.from_strings(rules:, deal: runde["deal"], dealer: runde["dealer"], actions: runde["actions"])
        assert_equal runde["phase"], round.phase.to_s
        assert_equal runde["actions"].split.size, runde["steps"].size
        assert_equal runde["result"]&.dig("points") || [], round.points
      end
    end
  ensure
    FileUtils.rm_f(path)
  end
end
