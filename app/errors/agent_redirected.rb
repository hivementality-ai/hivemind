# frozen_string_literal: true

class AgentRedirected < StandardError
  attr_reader :redirect_message

  def initialize(message)
    @redirect_message = message
    super("Agent redirected: #{message.truncate(100)}")
  end
end
