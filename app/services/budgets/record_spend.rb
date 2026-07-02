# frozen_string_literal: true

module Budgets
  # Record spending after LLM call
  class RecordSpend
    def self.call(agent:, cost_cents:, session: nil, provider: nil, llm_model: nil,
                  input_tokens: 0, output_tokens: 0, request_payload: nil)
      new(agent:, cost_cents:, session:, provider:, llm_model:,
          input_tokens:, output_tokens:, request_payload:).call
    end

    def initialize(agent:, cost_cents:, session: nil, provider: nil, llm_model: nil,
                   input_tokens: 0, output_tokens: 0, request_payload: nil)
      @agent = agent
      @cost_cents = cost_cents
      @session = session
      @provider = provider || agent.model_provider
      @llm_model = llm_model || agent.llm_model
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @request_payload = request_payload
    end

    def call
      ActiveRecord::Base.transaction do
        # Update all budget periods
        budgets = AgentBudget.where(agent: @agent)

        budgets.each do |budget|
          budget.increment!(:spent_cents, @cost_cents)

          # Check if exceeded or at warning threshold
          if budget.exceeded?
            handle_exceeded(budget)
          elsif budget.warning_threshold?
            handle_warning(budget)
          end
        end

        # Create usage record
        usage_record = UsageRecord.create!(
          agent: @agent,
          session: @session,
          provider: @provider,
          llm_model: @llm_model,
          input_tokens: @input_tokens,
          output_tokens: @output_tokens,
          cost_cents: @cost_cents,
          request_payload: @request_payload
        )

        # Broadcast budget update via ActionCable
        broadcast_update

        ServiceResponse.success(
          data: {
            recorded: true,
            usage_record: usage_record,
            budgets: budgets.map { |b| budget_summary(b) }
          }
        )
      end
    rescue => e
      ServiceResponse.failure(error: "Failed to record spend: #{e.message}")
    end

    private

    def handle_exceeded(budget)
      Rails.logger.warn "Agent #{@agent.id} exceeded #{budget.period_type} budget"
      BudgetAlertJob.perform_async(@agent.id, budget.id, "exceeded")
      return if budget.alerted_at?(100)

      budget.update_column(:last_alerted_threshold, 100)
      WebhookEmitter.emit(
        "budget.threshold",
        { agent_id: @agent.id, budget_id: budget.id, threshold: 100,
          period: budget.period_type, percentage_used: budget.percentage_used },
        agent: @agent
      )
    end

    def handle_warning(budget)
      Rails.logger.info "Agent #{@agent.id} at #{budget.percentage_used}% of #{budget.period_type} budget"
      BudgetAlertJob.perform_async(@agent.id, budget.id, "warning")
      return if budget.alerted_at?(80)

      budget.update_column(:last_alerted_threshold, 80)
      WebhookEmitter.emit(
        "budget.threshold",
        { agent_id: @agent.id, budget_id: budget.id, threshold: 80,
          period: budget.period_type, percentage_used: budget.percentage_used },
        agent: @agent
      )
    end

    def broadcast_update
      ActionCable.server.broadcast(
        "budgets_channel",
        {
          type: "budget_update",
          agent_id: @agent.id,
          cost_cents: @cost_cents,
          timestamp: Time.current.iso8601
        }
      )
    end

    def budget_summary(budget)
      {
        period_type: budget.period_type,
        spent_cents: budget.spent_cents,
        limit_cents: budget.limit_cents,
        remaining_cents: budget.remaining_cents,
        percentage_used: budget.percentage_used,
        exceeded: budget.exceeded?
      }
    end
  end
end
