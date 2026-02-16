# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent, type: :model do
  describe "slug generation and validation" do
    it "generates a slug from agent name on save" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      expect(agent.slug).to eq("test_agent")
    end

    it "generates slug with special characters converted" do
      agent = Agent.create!(name: "alice's-research_v2", role: "Helper")
      expect(agent.slug).to eq("alice_s-research_v2")
    end

    it "generates slug with uppercase converted to lowercase" do
      agent = Agent.create!(name: "RESEARCH BOT", role: "Helper")
      expect(agent.slug).to eq("research_bot")
    end

    it "generates slug from name with multiple spaces" do
      agent = Agent.create!(name: "My   Long   Agent   Name", role: "Helper")
      expect(agent.slug).to eq("my_long_agent_name")
    end

    it "does not regenerate slug if name changes after creation" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      original_slug = agent.slug
      
      agent.update!(name: "New Name")
      expect(agent.slug).to eq(original_slug)
    end

    it "auto-generates slug if not provided" do
      agent = Agent.new(name: "Test Agent", role: "Helper")
      agent.valid?
      expect(agent.slug).to eq("test_agent")
    end

    it "enforces unique slug (case-insensitive)" do
      Agent.create!(name: "Test Agent", role: "Helper")
      
      duplicate = Agent.new(name: "test_agent", role: "Helper")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include(/taken/)
    end

    it "enforces unique slug with different cases" do
      Agent.create!(name: "Test Agent", role: "Helper")
      
      duplicate = Agent.new(name: "TEST AGENT", role: "Helper")
      expect(duplicate).not_to be_valid
    end
  end

  describe ".find_by_slug" do
    it "finds agent by exact slug" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      found = Agent.find_by_slug("test_agent")
      expect(found).to eq(agent)
    end

    it "finds agent by slug case-insensitively" do
      agent = Agent.create!(name: "Test Agent", role: "Helper")
      
      expect(Agent.find_by_slug("Test_Agent")).to eq(agent)
      expect(Agent.find_by_slug("TEST_AGENT")).to eq(agent)
      expect(Agent.find_by_slug("test_agent")).to eq(agent)
    end

    it "returns nil for non-existent slug" do
      expect(Agent.find_by_slug("nonexistent")).to be_nil
    end
  end

  describe ".by_slug scope" do
    it "filters agents by slug case-insensitively" do
      agent1 = Agent.create!(name: "Test Agent", role: "Helper")
      Agent.create!(name: "Other Agent", role: "Helper")
      
      result = Agent.by_slug("TEST_AGENT")
      expect(result).to include(agent1)
      expect(result.count).to eq(1)
    end
  end
end
