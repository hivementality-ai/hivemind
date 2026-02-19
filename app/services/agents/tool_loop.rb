# frozen_string_literal: true

module Agents
  class ToolLoop
    MAX_ITERATIONS = 30

    def self.call(adapter:, agent:, session:, messages:, tools:, channel:, options: {}, broadcast_extras: {})
      new(adapter:, agent:, session:, messages:, tools:, channel:, options:, broadcast_extras:).call
    end

    def initialize(adapter:, agent:, session:, messages:, tools:, channel:, options: {}, broadcast_extras: {})
      @adapter = adapter
      @agent = agent
      @session = session
      @messages = messages.dup
      @tools = tools
      @channel = channel
      @options = options
      @broadcast_extras = broadcast_extras
      @full_content = +""
      @last_thinking = nil
      @total_usage = { input_tokens: 0, output_tokens: 0 }
    end

    def call
      iterations = 0
      llm_tools = @tools.map(&:to_llm_tool)

      loop do
        iterations += 1
        if iterations > MAX_ITERATIONS
          broadcast(type: "token", content: "\n\n⚠️ Tool loop limit reached (#{MAX_ITERATIONS} iterations)")
          break
        end

        # Call LLM
        result = call_llm(llm_tools)
        return result unless result&.success?

        data = result.data
        track_usage(data[:usage])

        # Capture thinking (hidden from user by default, stored as metadata)
        @last_thinking = data[:thinking] if data[:thinking].present?

        # Check for tool calls
        tool_calls = data[:tool_calls]

        if tool_calls.present?
          # Stream any text content before tool calls (narration — shown live but not stored)
          if data[:content].present?
            broadcast(type: "token", content: data[:content])
          end

          # Execute each tool call
          tool_results = execute_tool_calls(tool_calls)

          # Add assistant message with tool calls to conversation
          @messages << {
            role: "assistant",
            content: data[:content] || "",
            tool_calls: tool_calls
          }.with_indifferent_access

          # Add tool results to conversation
          tool_results.each do |tr|
            @messages << {
              role: "tool",
              tool_use_id: tr[:tool_use_id],
              tool_name: tr[:tool_name],
              content: tr[:result]
            }.with_indifferent_access
          end

          # Continue loop — LLM will process tool results
          next
        end

        # No tool calls — final text response
        content = data[:content].to_s
        Rails.logger.info("ToolLoop: final response content length=#{content.length}, content=#{content.first(200)}")
        if content.present?
          @full_content << content
          broadcast(type: "token", content: content)
        else
          Rails.logger.warn("ToolLoop: empty final response from LLM. Data keys: #{data.keys}")
        end

        break
      end

      ServiceResponse.success(data: {
        content: @full_content,
        thinking: @last_thinking,
        usage: @total_usage
      })
    end

    private

    def call_llm(llm_tools)
      @adapter.chat(
        messages: @messages,
        tools: llm_tools,
        options: @options
      )
    rescue StandardError => e
      ServiceResponse.failure(error: "LLM call failed: #{e.message}")
    end

    def execute_tool_calls(tool_calls)
      tool_calls.map do |tc|
        tool_name = tc["name"]
        tool_input = tc["input"] || {}
        tool_use_id = tc["id"]

        tool = @tools.find { |t| t.name == tool_name }

        unless tool
          explanation = Agents::ToolAvailability.explain(
            tool_name: tool_name,
            agent: @agent,
            available_tools: @tools
          )
          result = "Tool unavailable: #{explanation}"
          broadcast_tool(tool_name, tool_input, result, success: false)
          next { tool_use_id:, tool_name:, result: }
        end

        # Broadcast that we're running a tool
        broadcast(type: "tool_start", tool: tool_name, input: tool_input)

        # Execute
        exec_result = Tools::Executor.call(
          tool:,
          input: tool_input,
          agent: @agent,
          session: @session
        )

        if exec_result.success?
          result = exec_result.data[:output].to_s
          broadcast(type: "tool_result", tool: tool_name, output: result.truncate(500), success: true)
        else
          result = "Error: #{exec_result.error}"
          broadcast(type: "tool_result", tool: tool_name, output: result.truncate(500), success: false)
        end

        { tool_use_id:, tool_name:, result: }
      end
    end

    def track_usage(usage)
      return unless usage
      @total_usage[:input_tokens] += (usage[:input_tokens] || 0)
      @total_usage[:output_tokens] += (usage[:output_tokens] || 0)
    end

    def broadcast(data)
      ActionCable.server.broadcast(@channel, @broadcast_extras.merge(data))
    end

    def broadcast_tool(name, input, output, success:)
      broadcast(type: "tool_result", tool: name, output: output.to_s.truncate(500), success:)
    end
  end
end
