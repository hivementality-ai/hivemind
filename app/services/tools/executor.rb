# frozen_string_literal: true

module Tools
  class Executor
    NETWORK_EXECUTOR_TYPES = %w[http_request web_fetch browser].freeze

    BUILTIN_EXECUTORS = {
      "shell" => Tools::ShellExecutor,
      "sleep" => Tools::SleepExecutor,
      "file_read" => Tools::FileReadExecutor,
      "file_write" => Tools::FileWriteExecutor,
      "file_send" => Tools::FileSendExecutor,
      "web_search" => Tools::WebSearchExecutor,
      "web_fetch" => Tools::WebFetchExecutor,
      "browser" => Tools::BrowserExecutor,
      "memory_search" => Tools::MemorySearchExecutor,
      "memory_store" => Tools::MemoryStoreExecutor,
      "memory_update" => Tools::MemoryUpdateExecutor,
      "memory_stats" => Tools::MemoryStatsExecutor,
      "user_model" => Tools::UserModelExecutor,
      "user_model_populate" => Tools::UserModelPopulateExecutor,
      "file_edit" => Tools::FileEditExecutor,
      "image" => Tools::ImageExecutor,
      "image_generate" => Tools::ImageGenerateExecutor,
      "cron" => Tools::CronExecutor,
      "cron_script" => Tools::CronScriptExecutor,
      "message" => Tools::MessageExecutor,
      "heartbeat_write" => Tools::HeartbeatWriteExecutor,
      "delegate" => Tools::DelegateExecutor,
      "delegation_status" => Tools::DelegationStatusExecutor,
      "sessions_list" => Tools::SessionsListExecutor,
      "sessions_send" => Tools::SessionsSendExecutor,
      "sessions_history" => Tools::SessionsHistoryExecutor,
      "session_status" => Tools::SessionStatusExecutor,
      "session_search" => Tools::SessionSearchExecutor,
      "agents_list" => Tools::AgentsListExecutor,
      "gateway" => Tools::GatewayExecutor,
      "tts" => Tools::TtsExecutor,
      "gmail" => Tools::GmailExecutor,
      "drive" => Tools::CloudStorageExecutor,
      "cloud_storage" => Tools::CloudStorageExecutor,
      "http_request" => Tools::HttpRequestExecutor,
      "pdf_read" => Tools::PdfReadExecutor,
      "jira" => Tools::JiraExecutor,
      "trello" => Tools::TrelloExecutor,
      "email" => Tools::EmailExecutor,
      "custom_script" => Tools::CustomScriptExecutor,
      "coding_agent" => Tools::CodingAgentExecutor,
      "coding_agent_status" => Tools::CodingAgentStatusExecutor,
      "deep_research" => Tools::DeepResearchExecutor,
      "deep_research_status" => Tools::DeepResearchStatusExecutor,
      "vault" => Tools::VaultExecutor,
      "ask_user" => Tools::AskUserExecutor,
      "plan_mode" => Tools::PlanModeExecutor,
      "glob" => Tools::GlobExecutor,
      "load_skill" => Tools::LoadSkillExecutor,
      "canvas" => Tools::CanvasExecutor,
      "stt" => Tools::SttExecutor,
      "create_skill" => Tools::CreateSkillExecutor,
      "create_tool" => Tools::CreateToolExecutor,
      "google_drive" => Tools::GoogleDriveExecutor,
      "google_calendar" => Tools::GoogleCalendarExecutor,
      "google_gmail" => Tools::GoogleGmailExecutor,
      "project_create" => Tools::ProjectCreateExecutor,
      "project_update" => Tools::ProjectUpdateExecutor,
      "project_status" => Tools::ProjectStatusExecutor,
      "project_list" => Tools::ProjectListExecutor,
      "talk_to_teammate" => Tools::TalkToTeammateExecutor,
      "platform_control" => Tools::PlatformControlExecutor,
      "chat_attachments" => Tools::ChatAttachmentsExecutor,
      "grep" => Tools::GrepExecutor,
      "mcp" => Tools::McpExecutor,
      "task_manager" => Tools::TaskManagerExecutor
    }.freeze

    # Backwards compatibility alias
    EXECUTORS = BUILTIN_EXECUTORS

    class << self
      def call(tool:, input:, agent:, session:, extra_config: {})
        new(tool:, input:, agent:, session:, extra_config:).call
      end

      # Registers a plugin-provided executor type at runtime.
      #
      # @param type [String] executor type key (must match the tool's +executor_type+)
      # @param class_name [Class, String] executor class or its fully-qualified name
      def register(type, class_name)
        plugin_executors[type.to_s] = class_name.is_a?(String) ? class_name.constantize : class_name
      end

      # Removes a plugin-provided executor type.
      #
      # @param type [String] executor type key to remove
      def unregister(type)
        plugin_executors.delete(type.to_s)
      end

      # @return [Hash{String => Class}] merged map of builtin and plugin executors
      def all_executors
        BUILTIN_EXECUTORS.merge(plugin_executors)
      end

      # @param type [String] executor type key
      # @return [Boolean] true if a builtin or plugin executor is registered for this type
      def registered?(type)
        all_executors.key?(type.to_s)
      end

      # Clears all plugin-registered executors. Intended for tests.
      def reset_plugin_executors!
        @plugin_executors = {}
      end

      private

      def plugin_executors
        @plugin_executors ||= {}
      end
    end

    def initialize(tool:, input:, agent:, session:, extra_config: {})
      @tool = tool
      @input = input
      @agent = agent
      @session = session
      @extra_config = extra_config
    end

    def call
      executor_class = self.class.all_executors[@tool.executor_type]
      return ServiceResponse.failure(error: "Unknown executor: #{@tool.executor_type}") unless executor_class

      # System tools (e.g. load_skill) skip execution tracking
      if @tool.is_a?(SystemTool)
        return execute_system_tool(executor_class)
      end

      # Session-scoped file-read cache intercept.
      if file_read_tool? && (cache_hit = Tools::FileCache.try_read_hit(session: @session, path: file_path_input))
        execution = ToolExecution.create!(
          tool: @tool,
          agent: @agent,
          session: @session,
          input: @input,
          status: "completed",
          output: cache_hit[:output],
          raw_output: cache_hit[:output],
          exit_code: 0,
          duration_ms: 0
        )
        return ServiceResponse.success(data: { output: cache_hit[:output], execution_id: execution.id })
      end

      # Create execution record for regular tools
      execution = ToolExecution.create!(
        tool: @tool,
        agent: @agent,
        session: @session,
        input: @input,
        status: "running"
      )

      # Egress policy check for network tools
      if NETWORK_EXECUTOR_TYPES.include?(@tool.executor_type)
        target_url = extract_target_url
        if target_url.present?
          egress_result = NetworkEgress::PolicyCheck.call(agent: @agent, url: target_url)
          unless egress_result.allowed?
            execution.update!(status: "denied", error: "Egress blocked: #{egress_result.reason}")
            return ServiceResponse.failure(error: "Egress blocked: #{egress_result.reason}")
          end
        end
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        # Merge session into config for executors that need it
        executor_config = @tool.effective_config.merge(session: @session)
        Plugins::Hooks.trigger("before_tool_call", tool: @tool, input: @input, agent: @agent)
        result = executor_class.new(input: @input, config: executor_config, agent: @agent).call
        Plugins::Hooks.trigger("after_tool_call", tool: @tool, input: @input, agent: @agent, result: result)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i

        if result.success?
          raw_output = result.data[:output].to_s.truncate(50_000)
          compressed_output = Tools::OutputCompressor.compress(@tool.name, raw_output)
          execution.update!(
            status: "completed",
            output: compressed_output,
            raw_output: raw_output,
            exit_code: result.data[:exit_code],
            duration_ms: duration
          )
          update_file_cache_after_success!(raw_output)
          ServiceResponse.success(data: { output: compressed_output, execution_id: execution.id })
        else
          execution.update!(
            status: "failed",
            error: result.error,
            exit_code: result.data&.dig(:exit_code),
            duration_ms: duration
          )
          ServiceResponse.failure(error: result.error)
        end
      rescue AgentInterrupted, AgentRedirected
        raise
      rescue StandardError => e
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).to_i
        execution.update!(status: "failed", error: e.message, duration_ms: duration)
        ServiceResponse.failure(error: e.message)
      end
    end

    private

    FILE_READ_EXECUTORS = %w[file_read].freeze
    FILE_WRITE_EXECUTORS = %w[file_write file_edit].freeze

    def file_read_tool?
      FILE_READ_EXECUTORS.include?(@tool.executor_type.to_s)
    end

    def file_write_tool?
      FILE_WRITE_EXECUTORS.include?(@tool.executor_type.to_s)
    end

    def file_path_input
      @input.is_a?(Hash) ? (@input["path"] || @input[:path]) : nil
    end

    def update_file_cache_after_success!(raw_output)
      return unless @session
      path = file_path_input
      return if path.to_s.strip.empty?

      if file_read_tool?
        Tools::FileCache.record_read(session: @session, path: path, content: raw_output)
      elsif file_write_tool?
        Tools::FileCache.invalidate(session: @session, path: path)
      end
    end

    def extract_target_url
      case @tool.executor_type
      when "http_request"
        @input["url"].presence || @input["path"].presence
      when "web_fetch"
        @input["url"].presence
      when "browser"
        @input["url"].presence
      end
    end

    def execute_system_tool(executor_class)
      system_config = { session: @session }.merge(@extra_config || {})
      result = executor_class.new(input: @input, config: system_config, agent: @agent).call
      if result.success?
        ServiceResponse.success(data: { output: result.data[:output].to_s.truncate(50_000) })
      else
        ServiceResponse.failure(error: result.error)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end
  end
end
