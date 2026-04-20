# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskHookJob, type: :job do
  let(:agent) { create(:agent) }
  let(:task) { create(:task, assigned_to_agent: agent) }

  describe "#perform (deprecated shim)" do
    it "routes 'post' trigger to PostTransitionJob" do
      expect {
        described_class.new.perform(task.id, "done", "post", agent.id, "{}")
      }.to have_enqueued_job(Tasks::PostTransitionJob)
    end

    it "routes 'pre' trigger to PreTransitionJob" do
      expect {
        described_class.new.perform(task.id, "in_progress", "pre", agent.id, "{}")
      }.to have_enqueued_job(Tasks::PreTransitionJob)
    end

    it "ignores unknown triggers" do
      described_class.new.perform(task.id, "done", "unknown", agent.id, "{}")

      expect(Tasks::PreTransitionJob).not_to have_been_enqueued
      expect(Tasks::PostTransitionJob).not_to have_been_enqueued
    end

    it "handles missing task gracefully" do
      expect {
        described_class.new.perform(-1, "done", "post", nil, "{}")
      }.not_to raise_error
    end
  end
end
