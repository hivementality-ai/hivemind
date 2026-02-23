# frozen_string_literal: true

namespace :memory do
  desc "Import OpenClaw workspace memories into Hivemind agent"
  task :import_openclaw, [:path, :agent_slug] => :environment do |_t, args|
    path = args[:path] || ENV["OPENCLAW_WORKSPACE"] || File.expand_path("~/.openclaw/workspace")
    agent_slug = args[:agent_slug] || ENV["AGENT_SLUG"]

    unless File.directory?(path)
      puts "Error: Directory not found: #{path}"
      exit 1
    end

    result = Memory::OpenclawImporter.call(workspace_path: path, agent_slug: agent_slug)

    if result[:success]
      puts "\n✅ Import complete!"
      puts "   Agent: #{result[:agent_name]} (#{result[:agent_slug]})"
      puts "   Memories created: #{result[:memories_created]}"
      puts "   Files copied: #{result[:files_copied]}"
      puts "   Embeddings will be generated in the background via Sidekiq."
    else
      puts "\n❌ Import failed: #{result[:error]}"
      exit 1
    end
  end
end
