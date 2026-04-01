# frozen_string_literal: true

class TaskChannel < ApplicationCable::Channel
  def subscribed
    team = Team.find_by(id: params[:team_id])
    if team
      stream_from "tasks_#{team.id}"
    else
      reject
    end
  end

  def unsubscribed
    # Cleanup
  end
end
