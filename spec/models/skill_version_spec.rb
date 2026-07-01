# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillVersion, type: :model do
  let(:skill) { create(:skill, content: "Original content") }

  describe "validations" do
    # The skill factory's after_create snapshots an initial version (v1), so
    # clear it before exercising version_number uniqueness directly.
    before { skill.skill_versions.delete_all }

    it "is valid with required attributes" do
      version = build(:skill_version, skill: skill, version_number: 1)
      expect(version).to be_valid
    end

    it "requires version_number" do
      version = build(:skill_version, skill: skill, version_number: nil)
      expect(version).not_to be_valid
    end

    it "requires content" do
      version = build(:skill_version, skill: skill, content: nil)
      expect(version).not_to be_valid
    end

    it "enforces unique version_number per skill" do
      create(:skill_version, skill: skill, version_number: 1)
      duplicate = build(:skill_version, skill: skill, version_number: 1)
      expect(duplicate).not_to be_valid
    end

    it "allows same version_number on different skills" do
      other_skill = create(:skill)
      other_skill.skill_versions.delete_all
      create(:skill_version, skill: skill, version_number: 1)
      version = build(:skill_version, skill: other_skill, version_number: 1)
      expect(version).to be_valid
    end

    it "validates change_source inclusion" do
      version = build(:skill_version, skill: skill, change_source: "unknown_source")
      expect(version).not_to be_valid
    end
  end

  describe ".snapshot!" do
    before do
      # Clear auto-created versions from the skill factory callback
      skill.skill_versions.delete_all
    end

    it "creates a version with skill's current content" do
      version = described_class.snapshot!(skill: skill, change_source: "manual")
      expect(version.content).to eq(skill.content)
    end

    it "assigns version_number 1 for first snapshot" do
      version = described_class.snapshot!(skill: skill, change_source: "manual")
      expect(version.version_number).to eq(1)
    end

    it "increments version_number for subsequent snapshots" do
      described_class.snapshot!(skill: skill, change_source: "manual")
      second = described_class.snapshot!(skill: skill, change_source: "manual")
      expect(second.version_number).to eq(2)
    end

    it "computes the checksum from content" do
      version = described_class.snapshot!(skill: skill, change_source: "manual")
      expect(version.checksum).to eq(Digest::SHA256.hexdigest(skill.content))
    end

    it "stores optional attribution fields" do
      version = described_class.snapshot!(
        skill: skill,
        change_source: "agent_update",
        changed_by_user_id: 42,
        changed_by_agent_id: 7,
        change_summary: "Fixed typo",
        update_proposal_id: 99
      )
      expect(version.changed_by_user_id).to eq(42)
      expect(version.changed_by_agent_id).to eq(7)
      expect(version.change_summary).to eq("Fixed typo")
      expect(version.update_proposal_id).to eq(99)
    end
  end

  describe "scopes" do
    before { skill.skill_versions.delete_all }

    let!(:v1) { create(:skill_version, skill: skill, version_number: 1, created_at: 3.days.ago) }
    let!(:v2) { create(:skill_version, skill: skill, version_number: 2, created_at: 2.days.ago) }
    let!(:v3) { create(:skill_version, skill: skill, version_number: 3, created_at: 1.day.ago) }

    it "chronological orders oldest first" do
      expect(described_class.for_skill(skill).chronological.first).to eq(v1)
    end

    it "reverse_chronological orders newest first" do
      expect(described_class.for_skill(skill).reverse_chronological.first).to eq(v3)
    end
  end
end
