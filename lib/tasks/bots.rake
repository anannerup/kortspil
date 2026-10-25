namespace :bots do
  desc "Bot tournament (side metric): average points per runde per level (lower is better). Usage: bin/rails 'bots:tournament[spil,seed]'"
  task :tournament, %i[spil seed] => :environment do |_task, args|
    spil = (args[:spil] || 120).to_i
    started = Time.now
    report = Hjerterfri::Tournament.new(spil:, seed: (args[:seed] || 0).to_i).run

    puts "#{report.spil} spil, #{report.runder} runder (#{(Time.now - started).round(1)} s)"
    report.points_per_runde.sort_by(&:last).each do |level, points|
      puts format("  %-7s %6.2f point pr. runde   %d sejre", level, points, report.wins[level])
    end
  end

  desc "Duplicate: each deal played by every level with the same hand from the same seat against a fixed field (spec §8). Usage: bin/rails 'bots:duplicate[deals,seed,field]'"
  task :duplicate, %i[deals seed field] => :environment do |_task, args|
    started = Time.now
    field = (args[:field] || "mellem").to_sym
    report = Hjerterfri::Tournament.new(spil: (args[:deals] || 50).to_i, seed: (args[:seed] || 1).to_i).duplicate(field:)

    puts "#{report.deals} deals × 4 seats, field 3 × #{field} (#{(Time.now - started).round(1)} s)"
    report.points.each { |level, (mean, ci)| puts format("  %-7s %5.2f ± %4.2f point pr. runde", level, mean, ci) }
    puts "  same hand, same seat     better   same  worse   Δ point pr. runde"
    report.pairs.each do |(a, b), pair|
      mean, ci = pair[:difference]
      puts format("  %-6s vs %-6s       %5.1f %% %5.1f %% %5.1f %%   %+.2f ± %.2f", a, b, 100 * pair[:better], 100 * pair[:same], 100 * pair[:worse], mean, ci)
    end
  end

  desc "Parity: record the Ruby bots' decisions and check that the Rust botlab makes the same. Usage: bin/rails 'bots:parity[spil,seed]'"
  task :parity, %i[spil seed] => :environment do |_task, args|
    require Rails.root.join("tools/botlab/parity_record").to_s

    path = Rails.root.join("tmp/bot_parity.jsonl").to_s
    decisions = BotParity.record(path, spil: (args[:spil] || 40).to_i, seed: (args[:seed] || 1).to_i)
    puts "recorded #{decisions} lines in #{path}"
    manifest = Rails.root.join("tools/botlab/Cargo.toml").to_s
    system("cargo", "run", "--quiet", "--release", "--manifest-path", manifest, "--", "parity", path) || abort("parity failed")
  end
end
