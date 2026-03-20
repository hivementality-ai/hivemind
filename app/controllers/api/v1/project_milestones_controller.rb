# frozen_string_literal: true

module Api
  module V1
    class ProjectMilestonesController < ApiController
      before_action :set_project
      before_action :set_milestone, only: [ :show, :update, :approve, :reject ]

      def index
        milestones = @project.milestones.includes(:agent).ordered
        render json: milestones.map { |m| serialize(m) }
      end

      def show
        render json: serialize(@milestone, full: true)
      end

      def update
        if @milestone.update(milestone_params)
          render json: serialize(@milestone)
        else
          render json: { errors: @milestone.errors.full_messages }, status: :unprocessable_entity
        end
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
          summary: "Milestone approved via API: #{@milestone.title}"
        )

        render json: serialize(@milestone)
      end

      def reject
        feedback = params[:feedback].to_s.strip
        return render json: { error: "Feedback required" }, status: :unprocessable_entity if feedback.blank?

        new_retry = @milestone.retry_count + 1
        new_status = new_retry >= @milestone.max_retries ? "blocked" : "in_progress"

        @milestone.update!(
          status: new_status,
          reviewed_at: Time.current,
          review_notes: feedback,
          retry_count: new_retry
        )

        Projects::EventLogger.call(
          project: @project,
          milestone: @milestone,
          user: current_user,
          event_type: new_status == "blocked" ? "blocked" : "rejected",
          summary: "Milestone rejected via API: #{@milestone.title}"
        )

        if new_status == "in_progress"
          Projects::MilestoneRunner.call(milestone: @milestone, resume: true)
        end

        render json: serialize(@milestone)
      end

      private

      def set_project
        @project = Project.find(params[:project_id])
      end

      def set_milestone
        @milestone = @project.milestones.find(params[:id])
      end

      def milestone_params
        params.permit(:title, :description, :acceptance_criteria, :agent_id,
                      :requires_approval, :position)
      end

      def serialize(m, full: false)
        data = {
          id: m.id,
          project_id: m.project_id,
          title: m.title,
          description: m.description,
          status: m.status,
          position: m.position,
          agent_id: m.agent_id,
          agent_name: m.agent&.name,
          requires_approval: m.requires_approval,
          depends_on: m.depends_on,
          retry_count: m.retry_count,
          max_retries: m.max_retries,
          started_at: m.started_at&.iso8601,
          completed_at: m.completed_at&.iso8601,
          reviewed_at: m.reviewed_at&.iso8601
        }

        if full
          data[:acceptance_criteria] = m.acceptance_criteria
          data[:agent_notes] = m.agent_notes
          data[:review_notes] = m.review_notes
          data[:deliverables] = m.deliverables
          data[:checkpoint] = m.checkpoint
        end

        data
      end
    end
  end
end
