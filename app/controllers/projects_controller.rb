# frozen_string_literal: true

class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :pause, :resume, :cancel ]

  def index
    @projects = Project.includes(:team, :milestones).order(updated_at: :desc)
    @pending_approvals = ProjectMilestone.awaiting_review.count
  end

  def show
    @milestones = @project.milestones.includes(:agent, :session).ordered
    @events = @project.events.includes(:agent, :user, :project_milestone).recent.limit(50)
    @pending_milestones = @milestones.select { |m| m.status == "needs_review" }
  end

  def new
    @project = Project.new
    @teams = Team.includes(:agents).order(:name)
  end

  def create
    @project = Project.new(project_params)
    @project.user = current_user

    if @project.save
      if params[:ai_assisted] == "1" && @project.description.present?
        Projects::MilestonePlanner.call(project: @project)
      end

      if params[:milestones].present?
        create_manual_milestones
      end

      Projects::EventLogger.call(
        project: @project,
        user: current_user,
        event_type: "project_created",
        summary: "Project created: #{@project.title}"
      )

      redirect_to project_path(@project), notice: "Project created successfully."
    else
      @teams = Team.includes(:agents).order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      redirect_to project_path(@project), notice: "Project updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def pause
    @project.update!(status: "paused")
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project paused by #{current_user.email}")
    redirect_to project_path(@project), notice: "Project paused."
  end

  def resume
    @project.update!(status: "active", started_at: @project.started_at || Time.current)
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project resumed by #{current_user.email}")
    redirect_to project_path(@project), notice: "Project resumed."
  end

  def cancel
    @project.update!(status: "cancelled")
    Projects::EventLogger.call(project: @project, user: current_user,
      event_type: "status_change", summary: "Project cancelled by #{current_user.email}")
    redirect_to projects_path, notice: "Project cancelled."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :team_id, :priority, :deadline,
      notification_prefs: {})
  end

  def create_manual_milestones
    params[:milestones].each_with_index do |m, idx|
      next if m[:title].blank?
      @project.milestones.create!(
        title: m[:title],
        description: m[:description],
        acceptance_criteria: m[:acceptance_criteria],
        position: idx,
        requires_approval: m[:requires_approval] != "0",
        agent_id: m[:agent_id].presence
      )
    end
  end
end
