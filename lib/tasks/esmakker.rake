namespace :esmakker do
  desc "Parity: record seeded es-makker spil from the Ruby engine and replay them in the Python port. Usage: bin/rails 'esmakker:parity[spil,seed]' (PYTHON=… picks the interpreter)"
  task :parity, %i[spil seed] => :environment do |_task, args|
    require Rails.root.join("tools/esmakker_ai/parity_record").to_s

    path = Rails.root.join("tmp/esmakker_parity.jsonl.gz").to_s
    started = Time.now
    runder = EsmakkerParity.record(path, spil: (args[:spil] || 1000).to_i, seed: (args[:seed] || 1).to_i)
    puts "recorded #{runder} runder in #{path} (#{(Time.now - started).round(1)} s)"
    python = ENV.fetch("PYTHON", "python3")
    Dir.chdir(Rails.root.join("tools/esmakker_ai")) do
      system(python, "-m", "esmakker_ai.parity", path) || abort("parity failed")
    end
  end
end

namespace :esmakker do
  desc "Svær parity: record seeded spil played by Esmakker::Svaer (alone and with the first bot) and check the Python Svær makes every same decision and thought. Usage: bin/rails 'esmakker:svaer_parity[spil,seed]'"
  task :svaer_parity, %i[spil seed] => :environment do |_task, args|
    require Rails.root.join("tools/esmakker_ai/svaer_parity_record").to_s

    path = Rails.root.join("tmp/esmakker_svaer_parity.jsonl.gz").to_s
    started = Time.now
    counts = SvaerParity.record(path, spil: (args[:spil] || 1000).to_i, seed: (args[:seed] || 1).to_i)
    puts "recorded #{counts[:runder]} runder, #{counts[:decisions]} Svær decisions in #{path} (#{(Time.now - started).round(1)} s)"
    python = ENV.fetch("PYTHON", "python3")
    Dir.chdir(Rails.root.join("tools/esmakker_ai")) do
      system(python, "-m", "esmakker_ai.svaer_parity", path) || abort("Svær parity failed")
    end
  end
end
