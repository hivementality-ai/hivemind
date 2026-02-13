# frozen_string_literal: true

module HashtagActions
  class Processor
    # Orchestrates hashtag action execution.
    # Called from ChatStreamJob and InboundMessageJob before LLM processing.
    #
    # Returns a ProcessResult indicating:
    #   - Whether the LLM should still be called
    #   - Any direct response to send back
    #   - Any modifications to the system prompt or message

    ProcessResult = Struct.new(
      :bypass_llm,      # Boolean: skip LLM call entirely?
      :response,        # String: direct response to user (if bypass)
      :clean_message,   # String: cleaned user message (hashtags stripped)
      :prompt_addons,   # Array<String>: extra context to inject into system prompt
      :side_effects,    # Array<Hash>: log of what actions did
      keyword_init: true
    )

    def self.call(message:, agent:, session:, user: nil)
      new(message:, agent:, session:, user:).call
    end

    def initialize(message:, agent:, session:, user: nil)
      @message = message
      @agent = agent
      @session = session
      @user = user
    end

    def call
      parsed = Parser.call(message: @message)

      return pass_through if parsed.actions.empty?

      responses = []
      prompt_addons = []
      side_effects = []
      all_bypass = parsed.bypass_llm?

      parsed.actions.each do |action|
        executor = Registry.executor_for(action.name)
        next unless executor

        context = {
          agent: @agent,
          session: @session,
          user: @user,
          payload: action.payload,
          clean_message: parsed.clean_message
        }

        result = executor.call(**context)

        responses << result[:response] if result[:response].present?
        prompt_addons << result[:prompt_addon] if result[:prompt_addon].present?
        side_effects << { action: action.name, result: result[:status] || "ok" }

        # If any action says don't bypass, respect that
        all_bypass = false if result[:bypass] == false

        Rails.logger.info("[HashtagActions] Executed ##{action.name} for agent #{@agent.name}")
      end

      ProcessResult.new(
        bypass_llm: all_bypass,
        response: responses.join("\n\n"),
        clean_message: parsed.clean_message,
        prompt_addons: prompt_addons,
        side_effects: side_effects
      )
    rescue StandardError => e
      Rails.logger.error("[HashtagActions] Processing failed: #{e.message}")
      pass_through
    end

    private

    def pass_through
      ProcessResult.new(
        bypass_llm: false,
        response: nil,
        clean_message: @message,
        prompt_addons: [],
        side_effects: []
      )
    end
  end
end
