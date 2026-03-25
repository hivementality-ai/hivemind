# frozen_string_literal: true

class ProjectChannel < ApplicationCable::Channel
  def subscribed
    project = Project.find_by(id: params[:project_id])
    reject unless project

    stream_from "project_#{params[:project_id]}"
  end

  def unsubscribed
    # cleanup
  end
end
