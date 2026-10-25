namespace :bots do
  desc "Bot tournament: average points per runde per level (lower is better). Usage: bin/rails 'bots:tournament[spil,seed]'"
  task :tournament, %i[spil seed] => :environment do |_task, args|
    spil = (args[:spil] || 120).to_i
    started = Time.now
    report = Hjerterfri::Tournament.new(spil:, seed: (args[:seed] || 0).to_i).run

    puts "#{report.spil} spil, #{report.runder} runder (#{(Time.now - started).round(1)} s)"
    report.points_per_runde.sort_by(&:last).each do |level, points|
      puts format("  %-7s %6.2f point pr. runde   %d sejre", level, points, report.wins[level])
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
