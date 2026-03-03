# frozen_string_literal: true

module Tools
  class DeepResearchExecutor < BaseExecutor
    VALID_DEPTHS = %w[quick standard deep].freeze
    VALID_FOCUSES = %w[general technical scientific news financial].freeze
    VALID_FORMATS = %w[report bullet_points detailed_analysis executive_summary].freeze

    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      depth = input["depth"].to_s.strip.presence || "standard"
      unless VALID_DEPTHS.include?(depth)
        return ServiceResponse.failure(error: "Invalid depth. Allowed: #{VALID_DEPTHS.join(', ')}")
      end

      focus = input["focus"].to_s.strip.presence || "general"
      unless VALID_FOCUSES.include?(focus)
        return ServiceResponse.failure(error: "Invalid focus. Allowed: #{VALID_FOCUSES.join(', ')}")
      end

      output_format = input["output_format"].to_s.strip.presence || "report"
      unless VALID_FORMATS.include?(output_format)
        return ServiceResponse.failure(error: "Invalid output_format. Allowed: #{VALID_FORMATS.join(', ')}")
      end

      session = find_session
      return ServiceResponse.failure(error: "No session context available") unless session

      task_key = SecureRandom.hex(8)

      research_session = ResearchSession.create!(
        agent: agent || session.agent,
        session: session,
        query: query,
        depth: depth,
        focus: focus,
        output_format: output_format,
        task_key: task_key,
        status: "queued"
      )

      DeepResearchJob.perform_later(research_session.id)

      ServiceResponse.success(data: {
        output: "Started deep research (#{depth}): #{query.truncate(100)}\nTask ID: #{task_key}\nUse deep_research_status tool with this ID to check progress.",
        exit_code: 0,
        task_key: task_key
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to start deep research: #{e.message}")
    end

    private

    def find_session
      return config[:session] if config[:session]
      return nil unless agent
      Session.where(agent: agent).order(updated_at: :desc).first
    end
  end
end
