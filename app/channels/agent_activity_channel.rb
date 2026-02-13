# frozen_string_literal: true

class AgentActivityChannel < ApplicationCable::Channel
  def subscribed
    stream_from "agent_activity"
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
  end
end
