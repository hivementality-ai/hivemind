# frozen_string_literal: true

class SessionChannel < ApplicationCable::Channel
  def subscribed
    session = Session.find_by(id: params[:session_id])

    if session
      stream_from "session_#{session.id}"
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup
  end
end
