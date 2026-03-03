# frozen_string_literal: true

module OpenClaw
  class Migrator
    class ValidationError < StandardError; end

    OPTIONAL_MARKERS = %w[SOUL.md IDENTITY.md .openclaw MEMORY.md].freeze

    def self.call(workspace_path:, agent_slug: nil, dry_run: false)
      new(workspace_path:, agent_slug:, dry_run:).call
    end

    def initialize(workspace_path:, agent_slug: nil, dry_run: false)
      @workspace_path = workspace_path
      @agent_slug = agent_slug
      @dry_run = dry_run
    end

    def call
      report = MigrationReport.new(workspace_path: @workspace_path)
      validate!(report)

      ActiveRecord::Base.transaction do
        # 1. Identity (required — abort on failure)
        identity_result = IdentityParser.call(workspace_path: @workspace_path, agent_slug: @agent_slug)
        unless identity_result.success?
          report.add_warning("FATAL: #{identity_result.error}")
          raise ActiveRecord::Rollback
        end

        agent = identity_result.data[:agent]
        report.agent = agent
        report.identity_imported = true

        # 2. Memories (non-fatal)
        run_parser(report, "Memory") do
          result = MemoryParser.call(workspace_path: @workspace_path, agent: agent, dry_run: @dry_run)
          if result.success?
            report.memories_created = result.data[:count]
            report.memory_files_processed = result.data[:files_processed]
          end
          result
        end

        # 3. Skills (non-fatal)
        run_parser(report, "Skill") do
          result = SkillParser.call(workspace_path: @workspace_path, agent: agent)
          if result.success?
            report.skills_imported = result.data[:imported]
            report.skills_skipped = result.data[:skipped]
            report.skill_scan_results = result.data[:scan_results]
          end
          result
        end

        # 4. Channels (non-fatal)
        run_parser(report, "Channel") do
          result = ChannelParser.call(workspace_path: @workspace_path, agent: agent)
          if result.success?
            report.channels_created = result.data[:created]
            report.channels_skipped = result.data[:skipped]
          end
          result
        end

        # 5. Conversations (non-fatal)
        run_parser(report, "Conversation") do
          result = ConversationParser.call(workspace_path: @workspace_path, agent: agent)
          if result.success?
            report.sessions_created = result.data[:count]
          end
          result
        end

        # 6. Tools (non-fatal)
        run_parser(report, "Tool") do
          result = ToolParser.call(workspace_path: @workspace_path, agent: agent)
          if result.success?
            report.tools_created = result.data[:created]
            report.tools_skipped = result.data[:skipped]
          end
          result
        end

        # Dry run: roll back everything
        raise ActiveRecord::Rollback if @dry_run
      end

      ServiceResponse.success(data: { report: report })
    rescue ValidationError => e
      report = MigrationReport.new(workspace_path: @workspace_path)
      report.add_warning("FATAL: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    def validate!(report)
      raise ValidationError, "Directory does not exist: #{@workspace_path}" unless File.directory?(@workspace_path)

      config_path = File.join(@workspace_path, "config.json")
      raise ValidationError, "Missing config.json in #{@workspace_path}" unless File.exist?(config_path)

      OPTIONAL_MARKERS.each do |marker|
        path = File.join(@workspace_path, marker)
        report.markers_found << marker if File.exist?(path)
      end
    end

    def run_parser(report, name)
      result = yield
      unless result.success?
        report.add_warning("#{name} parser failed: #{result.error}")
      end
      result
    end
  end
end
