# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentTemplate, type: :model do
  subject { build(:agent_template) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:role) }
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:version) }

    it "validates category inclusion" do
      subject.category = "invalid"
      expect(subject).not_to be_valid
      expect(subject.errors[:category]).to be_present
    end

    AgentTemplate::CATEGORIES.each do |cat|
      it "accepts category '#{cat}'" do
        subject.category = cat
        expect(subject).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:featured) { create(:agent_template, featured: true) }
    let!(:regular) { create(:agent_template, featured: false) }

    it ".featured returns only featured templates" do
      expect(AgentTemplate.featured).to eq([ featured ])
    end

    it ".by_category filters by category" do
      expect(AgentTemplate.by_category(featured.category)).to include(featured)
    end

    it ".by_category returns all when nil" do
      expect(AgentTemplate.by_category(nil)).to include(featured, regular)
    end
  end

  describe "#deploy" do
    let(:template) { create(:agent_template) }

    it "calls CreateFromTemplate service" do
      expect(Agents::CreateFromTemplate).to receive(:call).with(
        template: template,
        name: "Custom Agent",
        team: nil
      )
      template.deploy(name: "Custom Agent")
    end
  end

  describe "#enabled_skill_names" do
    it "returns skill names from skills_config" do
      template = build(:agent_template, skills_config: { "enabled" => %w[github git] })
      expect(template.enabled_skill_names).to eq(%w[github git])
    end

    it "returns empty array when skills_config is empty" do
      template = build(:agent_template, skills_config: {})
      expect(template.enabled_skill_names).to eq([])
    end

    it "returns empty array when skills_config has no enabled key" do
      template = build(:agent_template, skills_config: { "other" => "value" })
      expect(template.enabled_skill_names).to eq([])
    end
  end

  describe "#enabled_tool_names" do
    it "returns tool names from tools_config" do
      template = build(:agent_template, tools_config: { "enabled" => %w[shell web_search] })
      expect(template.enabled_tool_names).to eq(%w[shell web_search])
    end

    it "returns empty array when tools_config is empty" do
      template = build(:agent_template, tools_config: {})
      expect(template.enabled_tool_names).to eq([])
    end

    it "returns empty array when tools_config has no enabled key" do
      template = build(:agent_template, tools_config: { "other" => "value" })
      expect(template.enabled_tool_names).to eq([])
    end
  end

  describe "skills_config" do
    it "defaults to empty hash" do
      template = build(:agent_template)
      expect(template.skills_config).to eq({})
    end

    it "accepts skills_config with enabled array" do
      template = build(:agent_template, skills_config: { enabled: [ "github", "git" ] })
      expect(template).to be_valid
      expect(template.skills_config["enabled"]).to eq([ "github", "git" ])
    end

    it "accepts empty skills_config" do
      template = build(:agent_template, skills_config: {})
      expect(template).to be_valid
    end
  end
end
