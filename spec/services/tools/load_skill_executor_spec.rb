# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::LoadSkillExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:config) { { session: session } }

  let!(:skill) do
    s = create(:skill, name: "github", enabled: true, tier: "manual",
                       summary: "GitHub CLI skill")
    agent.skills << s
    s
  end

  def executor(name)
    described_class.new(input: { "name" => name }, config: config, agent: agent)
  end

  describe "#call" do
    context "with a valid skill name" do
      it "returns success with skill content" do
        result = executor("github").call
        expect(result).to be_success
        expect(result.data[:output]).to eq(skill.content)
      end

      it "is case-insensitive" do
        result = executor("GITHUB").call
        expect(result).to be_success
      end

      it "records a manual SkillLoadEvent" do
        expect { executor("github").call }.to change(SkillLoadEvent, :count).by(1)
        event = SkillLoadEvent.last
        expect(event.skill).to eq(skill)
        expect(event.agent).to eq(agent)
        expect(event.session).to eq(session)
        expect(event.load_tier).to eq("manual")
        expect(event.relevance_score).to be_nil
      end
    end

    context "with a blank name" do
      it "returns failure with available skills listed" do
        result = executor("").call
        expect(result).to be_failure
        expect(result.error).to include("github")
      end

      it "does not record a load event" do
        expect { executor("").call }.not_to change(SkillLoadEvent, :count)
      end
    end

    context "with an unknown skill name" do
      it "returns failure" do
        result = executor("nonexistent-skill").call
        expect(result).to be_failure
        expect(result.error).to include("not found")
      end

      it "does not record a load event" do
        expect { executor("nonexistent-skill").call }.not_to change(SkillLoadEvent, :count)
      end
    end

    context "without a session in config" do
      let(:config) { {} }

      it "still returns skill content" do
        result = executor("github").call
        expect(result).to be_success
      end

      it "records event with nil session" do
        executor("github").call
        event = SkillLoadEvent.last
        expect(event.session).to be_nil
      end
    end
  end
end
