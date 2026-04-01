# frozen_string_literal: true

module Api
  module V1
    class TasksController < ApiController
      before_action :set_task, only: [ :show, :update, :destroy ]

      # GET /api/v1/tasks
      def index
        scope = Task.includes(:agent, :team, :session)

        scope = scope.for_team(Team.find(params[:team_id])) if params[:team_id].present?
        scope = scope.by_status(params[:status]) if params[:status].present?
        scope = scope.assigned_to(Agent.find_by!(slug: params[:agent_slug])) if params[:agent_slug].present?

        tasks = scope.order(priority: :desc, created_at: :desc).limit(100)
        render json: tasks.as_json(include: { agent: { only: [ :id, :name, :slug ] }, team: { only: [ :id, :name ] } })
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      end

      # GET /api/v1/tasks/:id
      def show
        render json: @task.as_json(include: { agent: { only: [ :id, :name, :slug ] }, team: { only: [ :id, :name ] }, session: { only: [ :id, :session_key, :title ] } })
      end

      # POST /api/v1/tasks
      def create
        @task = Task.new(task_params)
        @task.created_by = "user"

        if @task.save
          render json: @task, status: :created
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/tasks/:id
      def update
        if @task.update(task_params)
          render json: @task
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/tasks/:id
      def destroy
        @task.destroy
        head :no_content
      end

      private

      def set_task
        @task = Task.find(params[:id])
      end

      def task_params
        params.require(:task).permit(:title, :description, :status, :priority, :agent_id, :team_id, :session_id, :due_date)
      end
    end
  end
end
