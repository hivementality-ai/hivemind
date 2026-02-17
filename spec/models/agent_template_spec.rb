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
end
