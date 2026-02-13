# frozen_string_literal: true

module Api
  module V1
    class AgentsController < ApiController
      before_action :set_agent, only: [:show, :update, :destroy]

      def index
        @agents = Agent.visible.includes(:team).order(:name)
        render json: @agents.as_json(include: :team)
      end

      def show
        render json: @agent.as_json(
          include: :team,
          methods: [:current_status, :usage_summary]
        )
      end

      def create
        @agent = Agent.new(agent_params)

        if @agent.save
          render json: @agent, status: :created
        else
          render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @agent.update(agent_params)
          render json: @agent
        else
          render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @agent.destroy
        head :no_content
      end

      private

      def set_agent
        @agent = Agent.find(params[:id])
      end

      def agent_params
        params.require(:agent).permit(
          :name, :role, :team_id, :model_provider, :llm_model,
          :daily_budget_limit, :monthly_budget_limit, :workspace_path,
          :system_prompt, :enabled
        )
      end
    end
  end
end
