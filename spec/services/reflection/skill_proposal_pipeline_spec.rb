# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reflection::SkillProposalPipeline, type: :service do
  let(:team)  { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:task)  { create(:task, assigned_to_agent: agent, title: "Build reflective execution pipeline") }

  let(:reflection_with_novel) do
    {
      "went_well"       => [ "Existing pattern matching worked well" ],
      "was_hard"        => [ "Provider resolver chain required investigation" ],
      "do_differently"  => [ "Set up worktree first" ],
      "novel_solutions" => [ "Enqueue reflection on :low queue to avoid contending with hook pipeline" ],
      "key_insights"    => [ "Post-task reflection closes the agent self-improvement loop" ]
    }
  end

  let(:reflection_without_novel) do
    reflection_with_novel.merge("novel_solutions" => [])
  end

  let(:success_result) do
    ServiceResponse.success(data: { status: "pending_review", skill_id: 42 })
  end

  before do
    allow(Agents::SkillCreator).to receive(:call).and_return(success_result)
  end

  describe ".call" do
    context "when novel solutions are present" do
      it "calls SkillCreator" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).once
      end

      it "passes the agent correctly" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(agent: agent)
        )
      end

      it "generates a snake_case name from the task title and task id" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(name: match(/\Abuild_reflective_execution_pipeline_#{task.id}_/))
        )
      end

      it "includes novel solutions in the skill content" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(
            content: include("Enqueue reflection on :low queue")
          )
        )
      end

      it "uses 'utilities' category" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(category: "utilities")
        )
      end

      it "does not share with team by default" do
        described_class.call(agent: agent, task: task, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(share_with_team: false)
        )
      end
    end

    context "when novel solutions are empty" do
      it "skips SkillCreator entirely" do
        described_class.call(agent: agent, task: task, reflection: reflection_without_novel)

        expect(Agents::SkillCreator).not_to have_received(:call)
      end

      it "returns nil" do
        result = described_class.call(agent: agent, task: task, reflection: reflection_without_novel)
        expect(result).to be_nil
      end
    end

    context "when novel solutions are below minimum length" do
      let(:short_solutions) { reflection_with_novel.merge("novel_solutions" => [ "Used git" ]) }

      it "skips SkillCreator" do
        described_class.call(agent: agent, task: task, reflection: short_solutions)

        expect(Agents::SkillCreator).not_to have_received(:call)
      end
    end

    context "when SkillCreator rejects the proposal" do
      before do
        allow(Agents::SkillCreator).to receive(:call).and_return(
          ServiceResponse.failure(error: "Skill already exists")
        )
      end

      it "does not raise" do
        expect {
          described_class.call(agent: agent, task: task, reflection: reflection_with_novel)
        }.not_to raise_error
      end
    end

    context "with no task" do
      it "still generates a proposal using a fallback name" do
        described_class.call(agent: agent, task: nil, reflection: reflection_with_novel)

        expect(Agents::SkillCreator).to have_received(:call).with(
          hash_including(name: start_with("reflection_"))
        )
      end
    end
  end
end
