# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledTask, type: :model do
  describe 'associations' do
    it { should belong_to(:agent) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:schedule) }
    it { should validate_presence_of(:job_class) }
  end

  describe 'scopes' do
    let(:agent) { create(:agent) }
    let!(:enabled_task) { create(:scheduled_task, agent: agent, enabled: true) }
    let!(:disabled_task) { create(:scheduled_task, agent: agent, enabled: false) }
    let!(:other_agent_task) { create(:scheduled_task, enabled: true) }

    describe '.enabled' do
      it 'returns only enabled tasks' do
        expect(ScheduledTask.enabled).to include(enabled_task, other_agent_task)
        expect(ScheduledTask.enabled).not_to include(disabled_task)
      end
    end

    describe '.disabled' do
      it 'returns only disabled tasks' do
        expect(ScheduledTask.disabled).to include(disabled_task)
        expect(ScheduledTask.disabled).not_to include(enabled_task, other_agent_task)
      end
    end

    describe '.for_agent' do
      it 'returns tasks for specific agent' do
        expect(ScheduledTask.for_agent(agent)).to include(enabled_task, disabled_task)
        expect(ScheduledTask.for_agent(agent)).not_to include(other_agent_task)
      end
    end
  end

  describe '#enabled?' do
    it 'returns true when enabled is true' do
      task = build(:scheduled_task, enabled: true)
      expect(task.enabled?).to be true
    end

    it 'returns false when enabled is false' do
      task = build(:scheduled_task, enabled: false)
      expect(task.enabled?).to be false
    end
  end

  describe '#disabled?' do
    it 'returns false when enabled is true' do
      task = build(:scheduled_task, enabled: true)
      expect(task.disabled?).to be false
    end

    it 'returns true when enabled is false' do
      task = build(:scheduled_task, enabled: false)
      expect(task.disabled?).to be true
    end
  end

  describe '#last_run_status' do
    context 'when never run' do
      it 'returns never_run' do
        task = build(:scheduled_task, last_run_at: nil, last_error_at: nil)
        expect(task.last_run_status).to eq("never_run")
      end
    end

    context 'when last run was successful' do
      it 'returns success' do
        task = build(:scheduled_task, last_run_at: 1.hour.ago, last_error_at: nil)
        expect(task.last_run_status).to eq("success")
      end
    end

    context 'when last error is more recent than last run' do
      it 'returns error' do
        task = build(:scheduled_task, last_run_at: 2.hours.ago, last_error_at: 1.hour.ago)
        expect(task.last_run_status).to eq("error")
      end
    end

    context 'when error exists but no successful run' do
      it 'returns error' do
        task = build(:scheduled_task, last_run_at: nil, last_error_at: 1.hour.ago)
        expect(task.last_run_status).to eq("error")
      end
    end
  end

  describe 'factory' do
    it 'creates a valid scheduled task' do
      expect(build(:scheduled_task)).to be_valid
    end

    it 'creates valid tasks with traits' do
      expect(build(:scheduled_task, :daily)).to be_valid
      expect(build(:scheduled_task, :hourly)).to be_valid
      expect(build(:scheduled_task, :disabled)).to be_valid
      expect(build(:scheduled_task, :with_recent_run)).to be_valid
      expect(build(:scheduled_task, :with_error)).to be_valid
    end
  end
end
