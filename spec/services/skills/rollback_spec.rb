# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::Rollback, type: :service do
  let(:admin_id) { 1 }
  let(:skill)    { create(:skill, content: "Version 1 content.") }

  before do
    # skill already has v1 from the after_create callback
    # create v2 by updating content
    skill.update!(content: "Version 2 content.")
    skill.update!(content: "Version 3 content.")
  end

  describe ".call" do
    it "returns success when rolling back to a valid version" do
      v1 = skill.skill_versions.find_by(version_number: 1)
      result = described_class.call(skill: skill, version_number: v1.version_number, rolled_back_by: admin_id)
      expect(result).to be_success
    end

    it "replaces skill content with the target version's content" do
      v1 = skill.skill_versions.find_by(version_number: 1)
      described_class.call(skill: skill, version_number: v1.version_number, rolled_back_by: admin_id)
      expect(skill.reload.content).to eq(v1.content)
    end

    it "creates a new SkillVersion with change_source rollback" do
      v1 = skill.skill_versions.find_by(version_number: 1)
      expect {
        described_class.call(skill: skill, version_number: v1.version_number, rolled_back_by: admin_id)
      }.to change { skill.skill_versions.count }.by(1)

      latest = skill.skill_versions.order(version_number: :desc).first
      expect(latest.change_source).to eq("rollback")
    end

    it "includes the rollback summary in the new version" do
      v1 = skill.skill_versions.find_by(version_number: 1)
      described_class.call(skill: skill, version_number: v1.version_number, rolled_back_by: admin_id)
      latest = skill.skill_versions.order(version_number: :desc).first
      expect(latest.change_summary).to include("version #{v1.version_number}")
    end

    it "returns the rolled_back_to_version in data" do
      v1 = skill.skill_versions.find_by(version_number: 1)
      result = described_class.call(skill: skill, version_number: v1.version_number, rolled_back_by: admin_id)
      expect(result.data[:rolled_back_to_version]).to eq(v1.version_number)
    end

    context "when version does not exist" do
      it "returns failure" do
        result = described_class.call(skill: skill, version_number: 999, rolled_back_by: admin_id)
        expect(result).not_to be_success
        expect(result.error).to include("not found")
      end
    end

    context "when skill content already matches the target version" do
      it "returns failure" do
        current_version = skill.skill_versions.order(version_number: :desc).first
        result = described_class.call(skill: skill, version_number: current_version.version_number, rolled_back_by: admin_id)
        expect(result).not_to be_success
        expect(result.error).to include("already at this content")
      end
    end
  end
end
