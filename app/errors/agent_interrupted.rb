# frozen_string_literal: true

class AgentInterrupted < StandardError
  def initialize(msg = "Agent execution cancelled")
    super
  end
end
