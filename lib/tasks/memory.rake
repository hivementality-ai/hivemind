# frozen_string_literal: true

namespace :memory do
  desc "Backfill embeddings for MemoryEntry records missing them"
  task backfill_embeddings: :environment do
    batch_size = 50
    delay_between_batches = 1 # seconds (rate limiting)

    entries = MemoryEntry.where(embedding: nil)
    total = entries.count

    puts "Found #{total} memory entries without embeddings"

    entries.find_each(batch_size: batch_size).with_index do |entry, index|
      embedding = Memory::Embedding.generate(entry.content)

      if embedding
        entry.update!(embedding: embedding)
        print "."
      else
        print "x"
      end

      # Rate limit: pause between batches
      sleep(delay_between_batches) if (index + 1) % batch_size == 0
    end

    remaining = MemoryEntry.where(embedding: nil).count
    puts "\n\nDone! Backfilled #{total - remaining}/#{total} entries."
    puts "#{remaining} entries still missing embeddings." if remaining > 0
  end

  desc "Consolidate old episodic memories into typed summaries"
  task consolidate: :environment do
    # Find sessions with un-consolidated episodic memories
    session_ids = MemoryEntry.episodic.not_consolidated
                             .where("created_at < ?", 1.hour.ago)
                             .distinct.pluck(:source_id)

    puts "Found #{session_ids.size} sessions to consolidate"

    session_ids.each do |session_id|
      MemoryConsolidationJob.perform_later(session_id)
      print "."
    end

    puts "\nEnqueued #{session_ids.size} consolidation jobs"
  end

  desc "Show memory stats per agent"
  task stats: :environment do
    Agent.find_each do |agent|
      entries = MemoryEntry.where(agent: agent)
      next if entries.none?

      puts "\n#{agent.name} (#{agent.slug}):"
      puts "  Total:       #{entries.count}"
      puts "  Embedded:    #{entries.where.not(embedding: nil).count}"
      puts "  Types:       #{entries.group(:memory_type).count.map { |k, v| "#{k}=#{v}" }.join(', ')}"
      puts "  Consolidated: #{entries.consolidated.count}"
      puts "  Avg importance: #{entries.average(:importance)&.round(2) || 'n/a'}"
    end
  end

  desc "Clean up low-importance consolidated episodic memories older than 30 days"
  task cleanup: :environment do
    cutoff = 30.days.ago
    threshold = 0.3

    candidates = MemoryEntry.episodic.consolidated
                            .where("importance < ?", threshold)
                            .where("created_at < ?", cutoff)

    count = candidates.count
    puts "Found #{count} low-importance consolidated episodic memories older than 30 days"

    if count > 0
      print "Delete them? [y/N] "
      confirm = $stdin.gets.chomp
      if confirm.downcase == "y"
        candidates.destroy_all
        puts "Deleted #{count} entries"
      else
        puts "Cancelled"
      end
    end
  end
end
