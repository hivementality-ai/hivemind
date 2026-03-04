# frozen_string_literal: true

module Api
  module V1
    class AgentsController < ApiController
      before_action :set_agent, only: [ :show, :update, :destroy ]

      def index
        @agents = Agent.visible.includes(:team).order(:name)
        render json: @agents.as_json(include: :team)
      end

      def show
        render json: @agent.as_json(
          include: :team,
          methods: [ :current_status, :usage_summary ]
        )
      end

      def create
        @agent = Agent.new(agent_params)
        assign_restricted_attrs(@agent)

        if @agent.save
          render json: @agent, status: :created
        else
          render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        @agent.assign_attributes(agent_params)
        assign_restricted_attrs(@agent)
        if @agent.save
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
        @agent = Agent.find_by_slug(params[:slug])
        render json: { error: "Agent not found" }, status: :not_found unless @agent
      end

      def agent_params
        params.require(:agent).permit(
          :name, :team_id, :model_provider, :llm_model,
          :daily_budget_limit, :monthly_budget_limit, :workspace_path,
          :system_prompt, :enabled
        )
      end

      def assign_restricted_attrs(agent)
        ap = params[:agent]
        return unless ap

        agent.role = ap[:role] if ap.key?(:role)
        agent.egress_policy = build_egress_policy(ap[:egress_policy]) if ap.key?(:egress_policy)
      end

      def build_egress_policy(policy)
        return {} unless policy.is_a?(ActionController::Parameters)

        {
          "mode" => policy[:mode]&.to_s,
          "log_blocked" => ActiveModel::Type::Boolean.new.cast(policy[:log_blocked]),
          "rules" => Array(policy[:rules]).map { |r|
            { "pattern" => r[:pattern]&.to_s, "port" => r[:port]&.to_i }.compact_blank
          }
        }.compact
      end
    end
  end
end
