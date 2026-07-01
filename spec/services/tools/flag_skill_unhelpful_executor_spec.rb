# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::FlagSkillUnhelpfulExecutor, type: :service do
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:skill)   { create(:skill, name: "nav_skill", enabled: true) }
  let(:config)  { { session: session } }

  let(:valid_input) do
    {
      "skill_name" => skill.name,
      "reason"     => "Instructions were incomplete — missing the auth step."
    }
  end

  subject { described_class.new(input: valid_input, config: config, agent: agent) }

  describe "#call" do
    it "returns success for valid input" do
      expect(subject.call).to be_success
    end

    it "marks an existing load event as not helpful" do
      event = create(:skill_load_event, skill: skill, agent: agent, session: session, was_helpful: nil)
      subject.call
      expect(event.reload.was_helpful).to be false
    end

    it "stores the flagged reason on the load event" do
      event = create(:skill_load_event, skill: skill, agent: agent, session: session, was_helpful: nil)
      subject.call
      expect(event.reload.flagged_reason).to eq("Instructions were incomplete — missing the auth step.")
    end

    it "sets flagged_at on the event" do
      event = create(:skill_load_event, skill: skill, agent: agent, session: session, was_helpful: nil)
      subject.call
      expect(event.reload.flagged_at).to be_present
    end

    it "creates a new load event if none exists" do
      expect { subject.call }.to change(SkillLoadEvent, :count).by(1)
    end

    it "returns failure when skill_name is blank" do
      result = described_class.new(
        input: valid_input.merge("skill_name" => ""),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
    end

    it "returns failure when reason is blank" do
      result = described_class.new(
        input: valid_input.merge("reason" => ""),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
    end

    it "returns failure when skill does not exist" do
      result = described_class.new(
        input: valid_input.merge("skill_name" => "nonexistent"),
        config: config,
        agent: agent
      ).call
      expect(result).not_to be_success
      expect(result.error).to include("not found")
    end
  end
end
