# frozen_string_literal: true

module Sessions
  class Chat
    def self.call(...)
      new(...).call
    end

    def initialize(session:, message:, stream: false, agent: nil, &on_chunk)
      @session = session
      @message = message
      @stream = stream
      @on_chunk = on_chunk
    end

    def call
      agent = @session.agent

      # 1. Append user message to transcript
      @session.append_transcript({ "role" => "user", "content" => @message })

      # 2. Resolve the provider adapter
      resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
      return resolver unless resolver.success?

      adapter = resolver.data[:adapter]

      # 3. Budget enforcement — block over-budget agents before any LLM call
      budget_check = Budgets::Check.call(agent: agent)
      return ServiceResponse.failure(error: "Agent #{agent.name} has exceeded its budget for this period.") unless budget_check.success?

      # 3b. Shared orchestration budget — a delegation tree stops everywhere
      # once its combined spend crosses the ceiling, no matter which agent
      # or session the next call would come from.
      orchestration_id = @session.metadata&.dig("orchestration_id")
      if Delegations::OrchestrationBudget.exceeded?(orchestration_id)
        return ServiceResponse.failure(error: "Orchestration budget exhausted for this delegation tree.")
      end

      # 4. Build messages array (includes memory context, summary, transcript)
      message_result = Sessions::MessageBuilder.call(session: @session, agent: agent)
      messages = message_result.data[:messages]

      # 4. Resolve tools for this agent
      tools = resolve_tools(agent)

      # 5. Call the LLM
      options = { model: agent.llm_model, agent_id: agent.id, session_id: @session.id }

      # Detect OAuth/MCP proxy path (Anthropic OAuth tokens)
      base_adapter = Providers::FailoverAdapter.unwrap(adapter)
      oauth_mcp = base_adapter.is_a?(Providers::AnthropicAdapter) &&
                  (base_adapter.send(:api_key) rescue nil)&.start_with?("sk-ant-oat") &&
                  tools.any?

      if oauth_mcp
        # OAuth path: pass tool definitions for MCP bridge
        options[:tool_definitions] = tools.map { |t| t.respond_to?(:to_llm_tool) ? t.to_llm_tool : t }
      end

      if tools.any? && !oauth_mcp
        # ToolLoop path: full agentic tool execution for non-OAuth providers
        channel = "session_#{@session.session_key}"
        result = Agents::ToolLoop.call(
          adapter:, agent:, session: @session, messages:, tools:, channel:, options:
        )
        return result unless result&.success?

        content = result.data[:content].to_s
        usage = result.data[:usage] || {}
        tool_history = result.data[:tool_history]
      elsif @stream && @on_chunk
        response = adapter.chat(messages:, options:) do |chunk|
          @on_chunk.call(chunk)
        end
        return response unless response.success?
        content = response.data[:content]
        usage = response.data[:usage] || {}
        tool_history = nil
      else
        response = adapter.chat(messages:, options:)
        return response unless response.success?
        content = response.data[:content]
        usage = response.data[:usage] || {}
        tool_history = nil
      end

      # 6. Append assistant response to transcript (with tool history if present)
      transcript_entry = { "role" => "assistant", "content" => content }
      transcript_entry["tool_calls"] = tool_history if tool_history.present?
      @session.append_transcript(transcript_entry)

      # 7. Update token counts
      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0
      @session.update!(
        input_tokens: @session.input_tokens + input_tokens,
        output_tokens: @session.output_tokens + output_tokens,
        total_tokens: @session.total_tokens + input_tokens + output_tokens
      )

      # 8. Post-processing (usage, memory, summarization, origin delivery)
      Sessions::PostProcessor.call(
        agent: agent, session: @session,
        user_message: @message, assistant_response: content,
        usage: usage
      )

      # 9. Trigger consolidation for longer sessions (every 20 turns)
      maybe_consolidate

      ServiceResponse.success(data: { content:, usage:, tool_history: })
    rescue StandardError => e
      Rails.logger.error("[Sessions::Chat] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    # ----- Memory Consolidation -----
    # Different semantics from PostProcessor#maybe_summarize:
    # triggers MemoryConsolidationJob every 20 entries, not ConversationSummaryJob

    def resolve_tools(agent)
      assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
      tools = assigned.any? ? assigned : Tool.enabled.builtin.to_a
      tools << SystemTool::LOAD_SKILL if agent.skills.enabled.any?

      # Sessions at the delegation depth limit lose the delegate tool entirely
      # so the model never sees the option (Delegations::Request would reject
      # the call anyway — this avoids a wasted attempt).
      if @session.metadata&.dig("delegation_depth").to_i >= Delegations::Config.max_depth
        tools = tools.reject { |t| t.name == "delegate" }
      end

      tools
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Tool resolution failed: #{e.message}")
      []
    end

    def maybe_consolidate
      transcript_size = @session.transcript&.size || 0

      return unless transcript_size > 0 && (transcript_size % 20).zero?

      MemoryConsolidationJob.perform_later(@session.id)
    rescue StandardError => e
      Rails.logger.warn("[Sessions::Chat] Consolidation trigger failed: #{e.message}")
    end
  end
end
