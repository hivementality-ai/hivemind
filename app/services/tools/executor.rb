# frozen_string_literal: true

module Tools
  class Executor
    EXECUTORS = {
      "shell" => Tools::ShellExecutor,
      "file_read" => Tools::FileReadExecutor,
      "file_write" => Tools::FileWriteExecutor,
      "file_send" => Tools::FileSendExecutor,
      "web_search" => Tools::WebSearchExecutor,
      "web_fetch" => Tools::WebFetchExecutor,
      "browser" => Tools::BrowserExecutor,
      "memory_search" => Tools::MemorySearchExecutor,
      "file_edit" => Tools::FileEditExecutor,
      "image" => Tools::ImageExecutor,
      "image_generate" => Tools::ImageGenerateExecutor,
      "cron" => Tools::CronExecutor,
      "message" => Tools::MessageExecutor,
      "heartbeat_write" => Tools::HeartbeatWriteExecutor,
      "delegate" => Tools::DelegateExecutor,
      "spawn" => Tools::SpawnExecutor,
      "spawn_status" => Tools::SpawnStatusExecutor,
      "sessions_list" => Tools::SessionsListExecutor,
      "sessions_send" => Tools::SessionsSendExecutor,
      "sessions_history" => Tools::SessionsHistoryExecutor,
      "session_status" => Tools::SessionStatusExecutor,
      "agents_list" => Tools::AgentsListExecutor,
      "gateway" => Tools::GatewayExecutor,
      "tts" => Tools::TtsExecutor,
      "gmail" => Tools::GmailExecutor,
      "drive" => Tools::CloudStorageExecutor,
      "cloud_storage" => Tools::CloudStorageExecutor,
      "http_request" => Tools::HttpRequestExecutor,
      "pdf_read" => Tools::PdfReadExecutor,
      "jira" => Tools::JiraExecutor,
      "email" => Tools::EmailExecutor,
      "custom_script" => Tools::CustomScriptExecutor,
      "coding_agent" => Tools::CodingAgentExecutor,
      "coding_agent_status" => Tools::CodingAgentStatusExecutor,
      "vault" => Tools::VaultExecutor,
      "plan_mode" => Tools::PlanModeExecutor
    }.freeze

    def self.call(tool:, input:, agent:, session:)
      new(tool:, input:, agent:, session:).call
    end

    def initialize(tool:, input:, agent:, session:)
      @tool = tool
      @input = input
      @agent = agent
      @session = session
    end

    def call
      # Create execution record
      execution = ToolExecution.create!(
        tool: @tool,
        agent: @agent,
        session: @session,
        input: @input,
        status: "running"
      )

      executor_class = EXECUTORS[@tool.executor_type]
      unless executor_class
        execution.update!(status: "failed", error: "Unknown executor: #{@tool.executor_type}")
        return ServiceResponse.failure(error: "Unknown executor: #{@tool.executor_type}")
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        # Merge session into config for executors that need it
        executor_config = @tool.effective_config.merge(session: @session)
        result = executor_class.new(input: @input, config: executor_config, agent: @agent).call
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i

        if result.success?
          output = result.data[:output].to_s.truncate(50_000)
          execution.update!(
            status: "completed",
            output: output,
            exit_code: result.data[:exit_code],
            duration_ms: duration
          )
          ServiceResponse.success(data: { output: output, execution_id: execution.id })
        else
          execution.update!(
            status: "failed",
            error: result.error,
            exit_code: result.data&.dig(:exit_code),
            duration_ms: duration
          )
          ServiceResponse.failure(error: result.error)
        end
      rescue StandardError => e
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i
        execution.update!(status: "failed", error: e.message, duration_ms: duration)
        ServiceResponse.failure(error: e.message)
      end
    end
  end
end
