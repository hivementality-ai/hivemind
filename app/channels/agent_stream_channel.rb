# frozen_string_literal: true

class AgentStreamChannel < ApplicationCable::Channel
  def subscribed
    if params[:agent_id].present?
      stream_from "agent_stream_#{params[:agent_id]}"
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
  end
end
