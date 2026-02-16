# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubAgentTask, type: :model do
  describe 'associations' do
    it { should belong_to(:parent_agent).class_name('Agent') }
    it { should belong_to(:child_agent).class_name('Agent') }
    it { should belong_to(:parent_session).class_name('Session').optional }
    it { should belong_to(:child_session).class_name('Session').optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:task) }
    it { should validate_presence_of(:task_key) }

    describe 'uniqueness of task_key' do
      let!(:existing_task) { create(:sub_agent_task, task_key: 'unique-key') }

      it 'rejects duplicate task_keys' do
        new_task = build(:sub_agent_task, task_key: 'unique-key')
        expect(new_task).not_to be_valid
        expect(new_task.errors[:task_key]).to include('has already been taken')
      end
    end

    it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed]) }

    it 'validates presence of parent_agent_id' do
      task = build(:sub_agent_task, parent_agent: nil)
      expect(task).not_to be_valid
      expect(task.errors[:parent_agent]).to be_present
    end

    it 'validates presence of child_agent_id' do
      task = build(:sub_agent_task, child_agent: nil)
      expect(task).not_to be_valid
      expect(task.errors[:child_agent]).to be_present
    end
  end

  describe 'scopes' do
    let!(:pending_task) { create(:sub_agent_task, :pending) }
    let!(:running_task) { create(:sub_agent_task, :running) }
    let!(:completed_task) { create(:sub_agent_task, :completed) }
    let!(:failed_task) { create(:sub_agent_task, :failed) }

    describe '.active' do
      it 'returns pending and running tasks' do
        result = SubAgentTask.active
        expect(result).to include(pending_task, running_task)
        expect(result).not_to include(completed_task, failed_task)
      end
    end

    describe '.recent' do
      it 'returns tasks ordered by creation time, newest first' do
        # Create a task after others to ensure ordering
        new_task = create(:sub_agent_task)
        result = SubAgentTask.recent
        expect(result.first).to eq(new_task)
      end

      it 'limits to 20 results' do
        create_list(:sub_agent_task, 25)
        expect(SubAgentTask.recent.count).to eq(20)
      end
    end
  end

  describe '#duration_seconds' do
    context 'when not started' do
      let(:task) { create(:sub_agent_task, started_at: nil) }

      it 'returns nil' do
        expect(task.duration_seconds).to be_nil
      end
    end

    context 'when started but not completed' do
      let(:task) { create(:sub_agent_task, started_at: 10.seconds.ago, completed_at: nil) }

      it 'returns approximate duration to current time' do
        duration = task.duration_seconds
        expect(duration).to be_between(9, 11)
      end
    end

    context 'when started and completed' do
      let(:task) do
        create(:sub_agent_task,
               started_at: 5.seconds.ago,
               completed_at: Time.current)
      end

      it 'returns duration between start and completion' do
        duration = task.duration_seconds
        expect(duration).to be >= 0
        expect(duration).to be <= 6
      end
    end
  end

  describe 'factory' do
    it 'creates a valid task' do
      expect(build(:sub_agent_task)).to be_valid
    end

    it 'creates valid tasks with traits' do
      expect(build(:sub_agent_task, :pending)).to be_valid
      expect(build(:sub_agent_task, :running)).to be_valid
      expect(build(:sub_agent_task, :completed)).to be_valid
      expect(build(:sub_agent_task, :failed)).to be_valid
    end
  end
end
