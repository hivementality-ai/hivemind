# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostTaskReflectionJob, type: :job do
  let(:team)    { create(:team) }
  let(:agent)   { create(:agent, team: team) }
  let(:task)    { create(:task, assigned_to_agent: agent, title: "Build the feature", status: "done") }
  let(:session) { create(:session, agent: agent) }

  let(:reflection_response) do
    {
      "went_well"       => [ "Used the existing pattern correctly", "Tests passed first time" ],
      "was_hard"        => [ "Finding the right hook entry point took time" ],
      "do_differently"  => [ "Read all relevant specs before writing code" ],
      "novel_solutions" => [ "Injecting reflection trigger early before hook execution avoids timing issues" ],
      "key_insights"    => [ "Always check permissions on worktree files before editing" ]
    }.to_json
  end

  let(:adapter_double) do
    instance_double("Providers::BaseAdapter").tap do |d|
      allow(d).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: reflection_response })
      )
    end
  end

  let(:resolver_result) { ServiceResponse.success(data: { adapter: adapter_double }) }

  before do
    allow(Providers::Resolver).to receive(:call).and_return(resolver_result)
    allow(Memory::Store).to receive(:call).and_return(ServiceResponse.success(data: {}))
    allow(Agents::SkillCreator).to receive(:call).and_return(
      ServiceResponse.success(data: { status: "pending_review" })
    )
  end

  describe "#perform" do
    context "when the session has enough exchanges" do
      before do
        # Build a session with enough assistant turns
        3.times do
          session.transcript << { "role" => "user",      "content" => "Do this" }
          session.transcript << { "role" => "assistant", "content" => "Done" }
        end
        session.update!(metadata: { "task_id" => task.id })
        session.save!
      end

      it "calls the LLM and stores memories" do
        described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)

        expect(Memory::Store).to have_received(:call).at_least(1).times
      end

      it "uses the correct memory_type for key_insights" do
        described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)

        expect(Memory::Store).to have_received(:call).with(
          hash_including(memory_type: "procedural", agent: agent)
        ).at_least(:once)
      end

      it "triggers a skill proposal when novel_solutions are present" do
        described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)

        expect(Agents::SkillCreator).to have_received(:call).once
      end
    end

    context "when the session is too short" do
      before do
        session.transcript << { "role" => "user",      "content" => "Quick question" }
        session.transcript << { "role" => "assistant", "content" => "Quick answer" }
        session.save!
      end

      it "skips reflection without calling the LLM" do
        described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)

        expect(adapter_double).not_to have_received(:chat)
        expect(Memory::Store).not_to have_received(:call)
      end
    end

    context "when the LLM returns a low-quality reflection" do
      let(:low_quality_response) do
        {
          "went_well"       => [ "Fine" ],
          "was_hard"        => [ "N/A" ],
          "do_differently"  => [ "Nothing" ],
          "novel_solutions" => [],
          "key_insights"    => [ "Good" ]
        }.to_json
      end

      before do
        allow(adapter_double).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: low_quality_response })
        )
        3.times do
          session.transcript << { "role" => "user",      "content" => "Do something" }
          session.transcript << { "role" => "assistant", "content" => "Did it" }
        end
        session.save!
      end

      it "discards the reflection without persisting memories" do
        described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)

        expect(Memory::Store).not_to have_received(:call)
        expect(Agents::SkillCreator).not_to have_received(:call)
      end
    end

    context "when provider resolver fails" do
      before do
        allow(Providers::Resolver).to receive(:call).and_return(
          ServiceResponse.failure(error: "No provider configured")
        )
        3.times do
          session.transcript << { "role" => "user",      "content" => "Work" }
          session.transcript << { "role" => "assistant", "content" => "Done" }
        end
        session.save!
      end

      it "does not raise and skips reflection" do
        expect {
          described_class.new.perform(agent.id, task_id: task.id, session_id: session.id)
        }.not_to raise_error

        expect(Memory::Store).not_to have_received(:call)
      end
    end

    context "when agent is not found" do
      it "returns without error" do
        expect {
          described_class.new.perform(-1, task_id: task.id)
        }.not_to raise_error
      end
    end

    context "with no explicit session_id (resolves from task metadata)" do
      before do
        session.update!(metadata: { "task_id" => task.id })
        3.times do
          session.transcript << { "role" => "user",      "content" => "Task work" }
          session.transcript << { "role" => "assistant", "content" => "Completed" }
        end
        session.save!
      end

      it "finds the session from task metadata and reflects" do
        described_class.new.perform(agent.id, task_id: task.id)

        expect(Memory::Store).to have_received(:call).at_least(1).times
      end
    end
  end
end
