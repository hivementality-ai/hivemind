# frozen_string_literal: true

class ProjectDigestJob < ApplicationJob
  queue_as :low

  def perform(project_id)
    project = Project.find_by(id: project_id)
    return unless project

    Projects::DigestBuilder.call(project: project)
  end
end
