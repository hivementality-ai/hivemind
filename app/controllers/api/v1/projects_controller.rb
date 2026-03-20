# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < ApiController
      before_action :set_project, only: [ :show, :update ]

      def index
        projects = Project.includes(:team, :milestones).order(updated_at: :desc)
        projects = projects.where(status: params[:status]) if params[:status].present?
        projects = projects.where(team_id: params[:team_id]) if params[:team_id].present?

        render json: projects.map { |p| serialize_project(p) }
      end

      def show
        render json: serialize_project(@project, full: true)
      end

      def create
        project = Project.new(project_params)
        project.user = current_user

        if project.save
          Projects::EventLogger.call(
            project: project,
            user: current_user,
            event_type: "project_created",
            summary: "Project created via API: #{project.title}"
          )
          render json: serialize_project(project), status: :created
        else
          render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @project.update(project_params)
          render json: serialize_project(@project)
        else
          render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_project
        @project = Project.find(params[:id])
      end

      def project_params
        params.permit(:title, :description, :team_id, :priority, :deadline, :status)
      end

      def serialize_project(project, full: false)
        data = {
          id: project.id,
          title: project.title,
          description: project.description,
          status: project.status,
          priority: project.priority,
          team_id: project.team_id,
          team_name: project.team.name,
          progress: project.progress_percentage,
          deadline: project.deadline&.iso8601,
          started_at: project.started_at&.iso8601,
          completed_at: project.completed_at&.iso8601,
          created_at: project.created_at.iso8601,
          milestones_count: project.milestones.count,
          milestones_completed: project.milestones.where(status: "completed").count,
          pending_approvals: project.milestones.where(status: "needs_review").count
        }

        if full
          data[:milestones] = project.milestones.ordered.map { |m| serialize_milestone(m) }
          data[:recent_events] = project.events.recent.limit(20).map { |e| serialize_event(e) }
        end

        data
      end

      def serialize_milestone(m)
        {
          id: m.id,
          title: m.title,
          description: m.description,
          status: m.status,
          position: m.position,
          agent_id: m.agent_id,
          agent_name: m.agent&.name,
          requires_approval: m.requires_approval,
          retry_count: m.retry_count,
          started_at: m.started_at&.iso8601,
          completed_at: m.completed_at&.iso8601
        }
      end

      def serialize_event(e)
        {
          id: e.id,
          event_type: e.event_type,
          summary: e.summary,
          milestone_id: e.project_milestone_id,
          agent_name: e.agent&.name,
          created_at: e.created_at.iso8601
        }
      end
    end
  end
end
