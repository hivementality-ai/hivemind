# frozen_string_literal: true

class TeamChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "team_chat_#{params[:team_chat_session_id]}"
  end

  def unsubscribed
    # cleanup
  end
end
