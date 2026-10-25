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
end
