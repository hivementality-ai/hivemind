# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::AutoLoader, type: :service do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  let!(:core_skill) do
    skill = create(:skill, name: "core-skill", tier: "core", enabled: true,
                           tags: [], trigger_patterns: [],
                           summary: "Always on")
    agent.skills << skill
    skill
  end

  let!(:contextual_skill) do
    skill = create(:skill, name: "github", tier: "contextual", enabled: true,
                           tags: %w[github pr],
                           trigger_patterns: ["open.*pr", "github"],
                           summary: "GitHub CLI")
    agent.skills << skill
    skill
  end

  let!(:manual_skill) do
    skill = create(:skill, name: "weather", tier: "manual", enabled: true,
                           tags: %w[weather forecast],
                           trigger_patterns: ["weather"],
                           summary: "Weather info")
    agent.skills << skill
    skill
  end

  describe ".call" do
    context "with a relevant context" do
      let(:result) { described_class.call(agent: agent, session: session, context: "I need to open a PR on github") }

      it "returns core skills" do
        expect(result[:core_skills]).to include(core_skill)
      end

      it "returns contextual skills that match the context" do
        expect(result[:contextual_skills]).to include(contextual_skill)
      end

      it "does not return manual skills in contextual" do
        expect(result[:contextual_skills]).not_to include(manual_skill)
      end

      it "lists manual and unmatched skills in manual_skills" do
        expect(result[:manual_skills]).to include(manual_skill)
      end

      it "builds prompt blocks for core and contextual skills" do
        expect(result[:prompt_blocks]).to be_an(Array)
        expect(result[:prompt_blocks].any? { |b| b.include?("Contextual Skills") }).to be true
      end

      it "records a core load event" do
        expect { result }.to change(SkillLoadEvent, :count).by_at_least(1)
        core_event = SkillLoadEvent.find_by(skill: core_skill, agent: agent, load_tier: "core")
        expect(core_event).to be_present
      end

      it "records a contextual load event with relevance score" do
        result
        contextual_event = SkillLoadEvent.find_by(skill: contextual_skill, agent: agent, load_tier: "contextual")
        expect(contextual_event).to be_present
        expect(contextual_event.relevance_score).to be > 0
        expect(contextual_event.trigger_context).to include("github")
      end
    end

    context "with an irrelevant context" do
      let(:result) { described_class.call(agent: agent, session: session, context: "tell me a joke") }

      it "still returns core skills" do
        expect(result[:core_skills]).to include(core_skill)
      end

      it "returns no contextual skills" do
        expect(result[:contextual_skills]).to be_empty
      end
    end

    context "with blank context" do
      let(:result) { described_class.call(agent: agent, session: session, context: "") }

      it "returns no contextual skills" do
        expect(result[:contextual_skills]).to be_empty
      end
    end

    context "capping contextual skills" do
      before do
        # Create many contextual skills all matching
        4.times do |i|
          skill = create(:skill, name: "ctx-skill-#{i}", tier: "contextual", enabled: true,
                                 tags: %w[github], trigger_patterns: [],
                                 summary: "Contextual #{i}")
          agent.skills << skill
        end
      end

      it "limits contextual skills to MAX_CONTEXTUAL_SKILLS" do
        result = described_class.call(agent: agent, session: session, context: "github pr")
        expect(result[:contextual_skills].size).to be <= Skills::AutoLoader::MAX_CONTEXTUAL_SKILLS
      end
    end
  end
end
