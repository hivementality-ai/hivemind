# frozen_string_literal: true

module Agents
  class ToolLoop
    def self.call(adapter:, agent:, session:, messages:, tools:, channel:, options: {}, broadcast_extras: {}, extra_config: {})
      new(adapter:, agent:, session:, messages:, tools:, channel:, options:, broadcast_extras:, extra_config:).call
    end

    def initialize(adapter:, agent:, session:, messages:, tools:, channel:, options: {}, broadcast_extras: {}, extra_config: {})
      @adapter = adapter
      @agent = agent
      @session = session
      @messages = messages.dup
      @tools = tools
      @channel = channel
      @options = options
      @broadcast_extras = broadcast_extras
      @extra_config = extra_config
      @full_content = +""
      @last_thinking = nil
      @total_usage = { input_tokens: 0, output_tokens: 0 }
      @tool_history = []
      @loop_config = @agent.effective_tool_loop_config
      @context_manager = Agents::ContextManager.new(@agent.llm_model, @agent.max_output_tokens || 8192, provider: @agent.model_provider, agent: @agent)
      @decision_compactor = Agents::DecisionCompactor.new(context_manager: @context_manager, threshold: @context_manager.instance_variable_get(:@budget))
    end

    def call
      all_llm_tools = @tools.map(&:to_llm_tool)
      discovered_names = Set.new

      loop do
        # Check for interrupt signal before LLM call
        check_signal!

        # Filter tool schemas by detected task context to save tokens.
        active_llm_tools = filter_tools_for_turn(all_llm_tools, discovered_names)

        # Call LLM
        result = call_llm(active_llm_tools)
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

          # Record which tools got used so they stay in the schema for future turns.
          tool_calls.each { |tc| discovered_names << tc["name"] }

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

          # Feed milestone signals to the decision compactor.
          feed_decision_signals(tool_calls, tool_results)
          @messages = @decision_compactor.check!(@messages)

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
        usage: @total_usage,
        tool_history: @tool_history.map { |th| { tool: th[:tool_name], input: th[:params], output: th[:output].to_s.truncate(500), success: th[:success] } }
      })
    end

    private

    def call_llm(llm_tools)
      @adapter.chat(
        messages: @messages,
        tools: llm_tools,
        options: @options
      )
    rescue AgentInterrupted, AgentRedirected
      raise
    rescue StandardError => e
      ServiceResponse.failure(error: "LLM call failed: #{e.message}")
    end

    def feed_decision_signals(tool_calls, tool_results)
      edited_any = false
      tool_calls.each_with_index do |tc, i|
        name = tc["name"].to_s
        result = tool_results[i]
        success = !result[:result].to_s.start_with?("Error:") && !result[:result].to_s.start_with?("Tool unavailable")

        if %w[file_edit file_write].include?(name)
          path = (tc["input"] || {})["path"]
          @decision_compactor.signal_file_edited!(path) if path
          edited_any = true
        end

        if success && (name.include?("spec") || name.include?("test"))
          @decision_compactor.signal_specs_passed!
        end
      end

      @decision_compactor.signal_edit_batch_complete! if edited_any
    rescue StandardError => e
      Rails.logger.warn("[ToolLoop] decision-compactor signal failed: #{e.message}")
    end

    def filter_tools_for_turn(all_llm_tools, discovered_names)
      return all_llm_tools unless dynamic_tool_schema_enabled?

      last_user_msg = @messages.reverse.find { |m| (m[:role] || m["role"]).to_s == "user" }
      content = last_user_msg && (last_user_msg[:content] || last_user_msg["content"])
      message_text = extract_text(content)

      context = Agents::DynamicToolSchema.detect_context(message_text)
      Agents::DynamicToolSchema.filter(
        all_llm_tools,
        context: context,
        discovered_names: discovered_names.to_a
      )
    end

    def dynamic_tool_schema_enabled?
      config = @agent.respond_to?(:inference_options) ? @agent.inference_options : {}
      flag = config.is_a?(Hash) ? (config["dynamic_tool_schema_enabled"] || config[:dynamic_tool_schema_enabled]) : nil
      flag.nil? ? true : !!flag
    end

    def extract_text(content)
      case content
      when String then content
      when Array
        content.map do |block|
          block = block.to_h.with_indifferent_access rescue block
          block[:text] || block["text"] || ""
        end.join(" ")
      else
        ""
      end
    end

    def execute_tool_calls(tool_calls)
      results = tool_calls.map do |tc|
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
          session: @session,
          extra_config: @extra_config
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

      # Checkpoint project milestone progress periodically
      save_project_checkpoint if project_milestone_session? && (@tool_history.size % 10).zero? && @tool_history.size > 0

      results
    end

    def project_milestone_session?
      @session.metadata&.dig("type") == "project_milestone"
    end

    def save_project_checkpoint
      milestone_id = @session.metadata&.dig("milestone_id")
      return unless milestone_id

      milestone = ProjectMilestone.find_by(id: milestone_id)
      return unless milestone

      completed_steps = @tool_history.select { |t| t[:success] }.map do |t|
        "#{t[:tool_name]}: #{t[:output].to_s.truncate(100)}"
      end

      Projects::CheckpointWriter.call(
        milestone: milestone,
        agent: @agent,
        session: @session,
        completed_steps: completed_steps
      )
    rescue StandardError => e
      Rails.logger.warn("[ToolLoop] Project checkpoint failed: #{e.message}")
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
      # Keep the first request payload (most useful for debugging prompt structure)
      @total_usage[:request_payload] ||= usage[:request_payload]
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
