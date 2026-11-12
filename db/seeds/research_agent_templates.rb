# frozen_string_literal: true

# Public capability presets deliberately contain no personal souls or team data.
AgentTypes::PROFILES.each do |name, profile|
  template = AgentTemplate.find_or_initialize_by(name: name)
  next unless template.new_record?

  template.assign_attributes(
    role: name, description: profile[:summary], category: [ "Culinary Assistant", "Family Assistant", "Personal Assistant" ].include?(name) ? "lifestyle" : "research",
    author: "Hivemind", version: "1.0.0", model_config: {},
    tools_config: { enabled: profile[:tools].uniq }, skills_config: { enabled: profile[:skills] }
  )
  template.save!
end
