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
end
