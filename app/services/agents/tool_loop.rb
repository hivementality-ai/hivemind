# frozen_string_literal: true

module Agents
  class ToolLoop
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
      @tool_history = []
      @loop_config = @agent.effective_tool_loop_config
    end

    def call
      llm_tools = @tools.map(&:to_llm_tool)

      loop do
        # Check for interrupt signal before LLM call
        check_signal!

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

          # Execute each tool call and track in history
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

          # Analyze tool loop behavior
          loop_status = analyze_loop_behavior

          case loop_status
          when :warning
            inject_warning_message
          when :critical
            broadcast(type: "token", content: "\n\n⚠️ Tool loop detected - stopping to prevent infinite execution")
            break
          when :circuit_breaker
            broadcast(type: "token", content: "\n\n🚫 Circuit breaker activated - too many tool calls without progress")
            Rails.logger.error("Tool loop circuit breaker triggered for agent #{@agent.id} after #{@tool_history.size} calls")
            break
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

          # Track failed tool calls in history
          track_tool_call(tool_name, tool_input, result, false)

          next { tool_use_id:, tool_name:, result: }
        end

        # Check for interrupt signal before tool execution
        check_signal!

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
          result = sanitize_utf8(exec_result.data[:output].to_s)
          broadcast(type: "tool_result", tool: tool_name, output: result.truncate(500), success: true)
          track_tool_call(tool_name, tool_input, result, true)
        else
          result = sanitize_utf8("Error: #{exec_result.error}")
          broadcast(type: "tool_result", tool: tool_name, output: result.truncate(500), success: false)
          track_tool_call(tool_name, tool_input, result, false)
        end

        { tool_use_id:, tool_name:, result: }
      end
    end

    def check_signal!
      signal = SessionSignal.check(@session.id)
      return unless signal

      case signal[:type]
      when "cancel"
        Rails.logger.info("ToolLoop: cancel signal received for session #{@session.id}")
        raise AgentInterrupted
      when "redirect"
        Rails.logger.info("ToolLoop: redirect signal received for session #{@session.id}")
        raise AgentRedirected.new(signal[:message])
      when "inject"
        Rails.logger.info("ToolLoop: inject signal received for session #{@session.id}, injecting context")
        # Add the injected message to the conversation context
        @messages << { role: "user", content: signal[:message] }.with_indifferent_access
        broadcast(type: "inject", content: signal[:message])
      end
    end

    def track_usage(usage)
      return unless usage
      @total_usage[:input_tokens] += (usage[:input_tokens] || 0)
      @total_usage[:output_tokens] += (usage[:output_tokens] || 0)
    end

    def sanitize_utf8(str)
      str.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ").scrub(" ")
    end

    def broadcast(data)
      ActionCable.server.broadcast(@channel, @broadcast_extras.merge(data))
    end

    def broadcast_tool(name, input, output, success:)
      broadcast(type: "tool_result", tool: name, output: output.to_s.truncate(500), success:)
    end

    def track_tool_call(tool_name, params, output, success)
      @tool_history << {
        tool_name: tool_name,
        params: params,
        output: output,
        success: success,
        timestamp: Time.current
      }
    end

    def analyze_loop_behavior
      Agents::LoopDetector.analyze(
        tool_history: @tool_history,
        config: @loop_config
      )
    end

    def inject_warning_message
      warning_message = "You appear to be repeating the same action. Try a different approach."

      @messages << {
        role: "system",
        content: warning_message
      }.with_indifferent_access

      broadcast(type: "token", content: "\n\n⚠️ #{warning_message}\n")
    end
  end
end
