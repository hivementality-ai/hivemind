# frozen_string_literal: true

module Tools
  class CodingAgentExecutor < BaseExecutor
    DEFAULT_TIMEOUT = 600  # 10 minutes
    MAX_TIMEOUT = 1800     # 30 minutes
    ALLOWED_CLIS = %w[claude codex aider].freeze

    def call
      task = input["task"].to_s.strip
      cli = input["cli"].to_s.strip
      model = input["model"].to_s.strip
      timeout = input["timeout"].to_i

      # Validation
      return ServiceResponse.failure(error: "No task provided") if task.empty?

      cli = "claude" if cli.empty? # Default to claude
      return ServiceResponse.failure(error: "Invalid CLI. Allowed: #{ALLOWED_CLIS.join(', ')}") unless ALLOWED_CLIS.include?(cli)

      timeout = DEFAULT_TIMEOUT if timeout.zero?
      timeout = MAX_TIMEOUT if timeout > MAX_TIMEOUT

      # Security: sanitize task input to prevent shell injection
      return ServiceResponse.failure(error: "Task contains invalid characters") if task.include?("'") || task.include?("`") || task.include?("$")

      # Find session from context
      session = find_session
      return ServiceResponse.failure(error: "No session context available") unless session

      task_key = SecureRandom.hex(8)

      # Create coding agent task record
      coding_task = CodingAgentTask.create!(
        agent: agent || session.agent, # Use session's agent if no agent context
        session: session,
        task: task,
        cli: cli,
        model: model.presence,
        timeout: timeout,
        task_key: task_key,
        status: "pending"
      )

      # Start background job
      CodingAgentJob.perform_later(coding_task.id)

      ServiceResponse.success(data: {
        output: "🚀 Started #{cli} coding agent for: #{task.truncate(100)}\nTask ID: #{task_key}\nUse coding_agent_status tool with this ID to check progress.\n\nThe coding agent is running in the background with full workspace access. You'll see live progress updates in the chat.",
        exit_code: 0,
        task_key: task_key
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to start coding agent: #{e.message}")
    end

    private

    def find_session
      # Try to get session from config first (passed from executor)
      return config[:session] if config[:session]

      # Fallback: find the most recent session for this agent
      return nil unless agent
      Session.where(agent: agent).order(updated_at: :desc).first
    end
  end
end
