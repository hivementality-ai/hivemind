# frozen_string_literal: true

namespace :openclaw do
  desc "Migrate an OpenClaw workspace into Hivemind"
  task :migrate, [:path, :agent_slug] => :environment do |_t, args|
    path = args[:path] || ENV.fetch("OPENCLAW_WORKSPACE", File.expand_path("~/.openclaw"))
    agent_slug = args[:agent_slug] || ENV["AGENT_SLUG"]
    dry_run = ENV["DRY_RUN"] == "true"

    puts "OpenClaw Migration"
    puts "=" * 40
    puts "Workspace: #{path}"
    puts "Agent slug: #{agent_slug || '(auto-detect)'}"
    puts "Dry run: #{dry_run}"
    puts ""

    result = OpenClaw::Migrator.call(
      workspace_path: path,
      agent_slug: agent_slug,
      dry_run: dry_run
    )

    if result.success?
      report = result.data[:report]
      puts report.to_console

      # Save markdown report
      report_path = Rails.root.join("tmp", "openclaw_migration_report.md")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, report.to_markdown)
      puts ""
      puts "Report saved to: #{report_path}"
    else
      puts "Migration failed: #{result.error}"
      exit 1
    end
  end
end
