# frozen_string_literal: true

module Agents
  # Facade that coordinates the three compaction strategies: micro (every
  # turn, zero-cost), auto (LLM summarization when over budget or after a
  # prompt-too-long error), and manual (/compact). Ports rubyn-code's
  # context/compactor.rb.
  class Compactor
    CHARS_PER_TOKEN = 4

    def initialize(agent:, threshold: 50_000)
      @agent = agent
      @threshold = threshold
    end

    def micro_compact!(messages)
      Agents::MicroCompact.call(messages)
    end

    def auto_compact!(messages)
      Agents::AutoCompact.call(messages, agent: @agent)
    end

    def manual_compact!(messages, focus: nil)
      Agents::ManualCompact.call(messages, agent: @agent, focus: focus)
    end

    def should_auto_compact?(messages)
      estimated_tokens(messages) > @threshold
    end

    private

    def estimated_tokens(messages)
      json = JSON.generate(messages)
      (json.length.to_f / CHARS_PER_TOKEN).ceil
    rescue JSON::GeneratorError
      0
    end
  end
end
