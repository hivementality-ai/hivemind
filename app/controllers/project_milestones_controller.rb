# frozen_string_literal: true

class ProjectMilestonesController < ApplicationController
  before_action :set_project
  before_action :set_milestone, only: [ :show, :approve, :reject, :skip ]

  def show
    @dependency_milestones = @milestone.depends_on.present? ? @project.milestones.where(id: @milestone.depends_on) : []
    @events = @project.events.where(project_milestone: @milestone).order(created_at: :desc).limit(30)
  end

  def approve
    feedback = params[:feedback].to_s.strip

    @milestone.update!(
      status: "completed",
      completed_at: Time.current,
      reviewed_at: Time.current,
      review_notes: feedback.presence
    )

    Projects::EventLogger.call(
      project: @project,
      milestone: @milestone,
      user: current_user,
      event_type: "approved",
      summary: "Milestone approved: #{@milestone.title}#{feedback.present? ? " — #{feedback.truncate(100)}" : ''}"
    )

    ActionCable.server.broadcast("project_#{@project.id}", {
      type: "milestone_approved",
      milestone_id: @milestone.id,
      milestone_title: @milestone.title
    })

    redirect_to project_path(@project), notice: "Milestone approved."
  end

  def reject
    feedback = params[:feedback].to_s.strip

    if feedback.blank?
      redirect_to project_path(@project), alert: "Feedback is required when rejecting."
      return
    end

    new_retry = @milestone.retry_count + 1
    new_status = new_retry >= @milestone.max_retries ? "blocked" : "in_progress"

    @milestone.update!(
      status: new_status,
      reviewed_at: Time.current,
      review_notes: feedback,
      retry_count: new_retry
    )

    event_type = new_status == "blocked" ? "blocked" : "rejected"
    Projects::EventLogger.call(
      project: @project,
      milestone: @milestone,
      user: current_user,
      event_type: event_type,
      summary: "Milestone #{event_type}: #{@milestone.title} — #{feedback.truncate(100)}"
    )

    if new_status == "in_progress"
      Projects::MilestoneRunner.call(milestone: @milestone, resume: true)
    end

    ActionCable.server.broadcast("project_#{@project.id}", {
      type: "milestone_rejected",
      milestone_id: @milestone.id,
      new_status: new_status
    })

    redirect_to project_path(@project), notice: "Milestone rejected with feedback."
  end

  def skip
    @milestone.update!(status: "skipped")
    Projects::EventLogger.call(
      project: @project,
      milestone: @milestone,
      user: current_user,
      event_type: "status_change",
      summary: "Milestone skipped: #{@milestone.title}"
    )
    redirect_to project_path(@project), notice: "Milestone skipped."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_milestone
    @milestone = @project.milestones.find(params[:id])
  end
end
