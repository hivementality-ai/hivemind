# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BudgetAlertJob, type: :job do
  include ActiveJob::TestHelper

  let(:agent) { create(:agent) }
  let(:budget) { create(:agent_budget, :warning, agent: agent) }

  describe '#perform' do
    it 'broadcasts a warning notification via ActionCable' do
      expect(ActionCable.server).to receive(:broadcast).with(
        "notifications_channel",
        hash_including(
          type: "budget_alert",
          severity: "warning",
          agent_id: agent.id,
          budget_id: budget.id
        )
      )

      described_class.new.perform(agent.id, budget.id, "warning")
    end

    it 'broadcasts an error notification when budget is exceeded' do
      exceeded_budget = create(:agent_budget, :exceeded, agent: agent)

      expect(ActionCable.server).to receive(:broadcast).with(
        "notifications_channel",
        hash_including(
          type: "budget_alert",
          severity: "error"
        )
      )

      described_class.new.perform(agent.id, exceeded_budget.id, "exceeded")
    end

    it 'enqueues an Audit::Record with correct arguments' do
      allow(ActionCable.server).to receive(:broadcast)

      expect(Audit::Record).to receive(:call).with(
        actor_type: "system",
        actor_id: "system",
        action: "budget.alert_sent",
        resource: "agents/#{agent.id}",
        metadata: {
          budget_id: budget.id,
          alert_type: "warning",
          percentage_used: budget.percentage_used
        }
      )

      described_class.new.perform(agent.id, budget.id, "warning")
    end

    it 'logs the alert message' do
      allow(ActionCable.server).to receive(:broadcast)
      allow(Audit::Record).to receive(:call)

      expect(Rails.logger).to receive(:warn).with(/Agent '#{agent.name}'.*#{budget.percentage_used}%/)

      described_class.new.perform(agent.id, budget.id, "warning")
    end

    it 'handles an unknown alert_type gracefully' do
      allow(ActionCable.server).to receive(:broadcast)
      allow(Audit::Record).to receive(:call)

      expect(Rails.logger).to receive(:warn).with("Budget alert for agent '#{agent.name}'")

      described_class.new.perform(agent.id, budget.id, "unknown")
    end

    it 'raises ActiveRecord::RecordNotFound for missing agent' do
      allow(ActionCable.server).to receive(:broadcast)

      expect {
        described_class.new.perform(-1, budget.id, "warning")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises ActiveRecord::RecordNotFound for missing budget' do
      allow(ActionCable.server).to receive(:broadcast)

      expect {
        described_class.new.perform(agent.id, -1, "warning")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
