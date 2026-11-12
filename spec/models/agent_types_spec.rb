# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentTypes do
  it "seeds reusable templates without embedding identities or overwriting customization" do
    path = Rails.root.join("db/seeds/research_agent_templates.rb")
    load path
    template = AgentTemplate.find_by!(name: "Family Assistant")
    template.update!(description: "Customized description")
    expect { load path }.not_to change(AgentTemplate, :count)
    expect(template.reload.description).to eq("Customized description")
    described_class::PROFILES.each do |name, profile|
      seeded = AgentTemplate.find_by!(name: name)
      expect(seeded.role).to eq(name)
      expect(seeded.soul_md).to be_blank
      expect(seeded.enabled_tool_names).to match_array(profile[:tools].uniq)
      expect(described_class.instructions(name)).to be_present
    end
  end

  it "keeps personal types free of the research-specific protocol" do
    %w[Personal Family Culinary].each do |kind|
      expect(described_class.instructions("#{kind} Assistant")).not_to include(described_class::RESEARCH_STANDARDS)
    end
  end
end
