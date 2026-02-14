# frozen_string_literal: true

module Tools
  class Executor
    EXECUTORS = {
      "shell" => Tools::ShellExecutor,
      "file_read" => Tools::FileReadExecutor,
      "file_write" => Tools::FileWriteExecutor,
      "web_search" => Tools::WebSearchExecutor,
      "web_fetch" => Tools::WebFetchExecutor
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
        result = executor_class.new(input: @input, config: @tool.config, agent: @agent).call
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
