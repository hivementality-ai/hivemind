# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reflection::MemoryPipeline, type: :service do
  let(:team)  { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:task)  { create(:task, assigned_to_agent: agent, title: "Implement reflection pipeline") }

  let(:reflection) do
    {
      "went_well"       => [ "Matched existing code patterns from nearby files" ],
      "was_hard"        => [ "Resolving the provider adapter chain took iteration" ],
      "do_differently"  => [ "Check file permissions before writing worktree files" ],
      "novel_solutions" => [ "Using perform_later on :low queue prevents blocking hook pipeline" ],
      "key_insights"    => [ "Post-task reflection closes the agent learning loop" ]
    }
  end

  before do
    allow(Memory::Store).to receive(:call).and_return(ServiceResponse.success(data: {}))
  end

  describe ".call" do
    it "stores memories for each non-empty reflection section" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      # 5 sections x 1 item each = 5 calls
      expect(Memory::Store).to have_received(:call).exactly(5).times
    end

    it "stores all memories with category: learned_behavior" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(category: "learned_behavior")
      ).exactly(5).times
    end

    it "stores key_insights as procedural memories" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(
          agent:       agent,
          memory_type: "procedural",
          importance:  0.8,
          category:    "learned_behavior"
        )
      )
    end

    it "stores went_well as semantic memories" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(
          agent:       agent,
          memory_type: "semantic",
          importance:  0.55,
          category:    "learned_behavior"
        )
      )
    end

    it "stores novel_solutions as procedural memories with highest importance" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(
          agent:       agent,
          memory_type: "procedural",
          importance:  0.85,
          category:    "learned_behavior"
        )
      )
    end

    it "tags memories with post_task_reflection source" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(
          metadata: hash_including("source" => "post_task_reflection")
        )
      ).at_least(:once)
    end

    it "includes task_id in metadata" do
      described_class.call(agent: agent, task: task, reflection: reflection)

      expect(Memory::Store).to have_received(:call).with(
        hash_including(
          metadata: hash_including("task_id" => task.id)
        )
      ).at_least(:once)
    end

    it "skips empty sections without storing memories" do
      sparse = reflection.merge("novel_solutions" => [], "was_hard" => [])
      described_class.call(agent: agent, task: task, reflection: sparse)

      # Only 3 non-empty sections remain
      expect(Memory::Store).to have_received(:call).exactly(3).times
    end

    it "returns the count of stored memories" do
      count = described_class.call(agent: agent, task: task, reflection: reflection, score: 0.7)
      expect(count).to eq(5)
    end

    it "works without a task (session-level reflection)" do
      expect {
        described_class.call(agent: agent, task: nil, reflection: reflection)
      }.not_to raise_error

      expect(Memory::Store).to have_received(:call).exactly(5).times
    end

    context "when Memory::Store raises" do
      before do
        allow(Memory::Store).to receive(:call).and_raise(StandardError, "Redis down")
      end

      it "does not propagate the error" do
        expect {
          described_class.call(agent: agent, task: task, reflection: reflection)
        }.not_to raise_error
      end

      it "returns 0" do
        count = described_class.call(agent: agent, task: task, reflection: reflection)
        expect(count).to eq(0)
      end
    end
  end
end
