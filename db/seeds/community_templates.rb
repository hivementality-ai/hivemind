# frozen_string_literal: true

# Community Agent Templates
# Imports agent templates from msitarzewski/agency-agents (MIT licensed).
# Source: https://github.com/msitarzewski/agency-agents
#
# Usage:
#   git clone --depth 1 https://github.com/msitarzewski/agency-agents.git /tmp/agency-agents
#   rails db:seed
#
# The source repo must be cloned before seeding. Set AGENCY_AGENTS_PATH to
# override the default location.

require "yaml"

SOURCE_PATH = ENV.fetch("AGENCY_AGENTS_PATH", "/tmp/agency-agents")

SKIP_DIRS = %w[.git .github integrations examples scripts strategy].freeze

# === Category Mapping ===

DIRECTORY_CATEGORY_MAP = {
  "engineering" => "coding",
  "design" => "design",
  "marketing" => "marketing",
  "paid-media" => "marketing",
  "product" => "project",
  "project-management" => "project",
  "sales" => "sales",
  "support" => "support",
  "testing" => "testing",
  "game-development" => "gamedev",
  "spatial-computing" => "specialized",
  "specialized" => "specialized"
}.freeze

# === Tool Mapping ===

DIRECTORY_TOOLS_MAP = {
  "engineering" => %w[shell file_read file_write file_edit web_search web_fetch memory_search coding_agent coding_agent_status],
  "design" => %w[web_search web_fetch browser memory_search image image_generate file_write],
  "marketing" => %w[web_search web_fetch browser memory_search file_write file_read],
  "paid-media" => %w[web_search web_fetch browser memory_search file_write http_request],
  "product" => %w[web_search web_fetch memory_search file_write],
  "project-management" => %w[web_search web_fetch memory_search file_write delegate spawn],
  "sales" => %w[web_search web_fetch memory_search file_write email http_request],
  "support" => %w[web_search web_fetch memory_search email file_write],
  "testing" => %w[shell file_read file_write file_edit web_search web_fetch browser memory_search],
  "game-development" => %w[shell file_read file_write file_edit web_search web_fetch memory_search coding_agent coding_agent_status],
  "spatial-computing" => %w[shell file_read file_write file_edit web_search web_fetch memory_search coding_agent],
  "specialized" => %w[web_search web_fetch memory_search file_write file_read]
}.freeze

# === Skills Mapping ===

DIRECTORY_SKILLS_MAP = {
  "engineering" => %w[github git docker],
  "testing" => %w[github git],
  "project-management" => %w[github],
  "game-development" => %w[github git],
  "support" => [],
  "design" => [],
  "marketing" => [],
  "paid-media" => [],
  "product" => [],
  "sales" => [],
  "spatial-computing" => %w[github git],
  "specialized" => []
}.freeze

# === Model Config ===

DIRECTORY_MODEL_MAP = {
  "engineering" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.3 },
  "design" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.5 },
  "marketing" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.5 },
  "paid-media" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.4 },
  "product" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.4 },
  "project-management" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.3 },
  "sales" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.4 },
  "support" => { provider: "anthropic", model: "claude-haiku-4-5", temperature: 0.5 },
  "testing" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.2 },
  "game-development" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.3 },
  "spatial-computing" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.3 },
  "specialized" => { provider: "anthropic", model: "claude-sonnet-4-5", temperature: 0.4 }
}.freeze

# === Featured Templates ===

FEATURED_NAMES = Set.new(%w[
  Frontend\ Developer
  Backend\ Architect
  DevOps\ Automator
  Security\ Engineer
  AI\ Engineer
  UI\ Designer
  UX\ Researcher
  Growth\ Hacker
  Content\ Creator
  SEO\ Specialist
  Sprint\ Prioritizer
  Senior\ Project\ Manager
  Analytics\ Reporter
  Support\ Responder
  API\ Tester
  Performance\ Benchmarker
  Technical\ Writer
  Deal\ Strategist
  Compliance\ Auditor
  Developer\ Advocate
  Game\ Designer
  Mobile\ App\ Builder
  Software\ Architect
  Senior\ Developer
]).freeze

# === Parsing ===

def parse_frontmatter(text)
  return [{}, text] unless text.start_with?("---")

  parts = text.split("---", 3)
  return [{}, text] if parts.length < 3

  frontmatter = YAML.safe_load(parts[1], permitted_classes: [Symbol]) || {}
  body = parts[2].strip
  [frontmatter, body]
rescue Psych::SyntaxError
  [{}, text]
end

def parse_sections(body)
  sections = {}
  current_key = "_intro"
  current_lines = []

  body.each_line do |line|
    if line.start_with?("## ")
      sections[current_key] = current_lines.join.strip
      # Strip emoji prefixes from section names
      current_key = line.sub(/^##\s+/, "").gsub(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]\s*/, "").strip
      current_lines = []
    else
      current_lines << line
    end
  end
  sections[current_key] = current_lines.join.strip
  sections
end

def generate_icon(name)
  words = name.split(/[\s\-]+/).reject { |w| w.length < 2 }
  if words.length >= 2
    (words[0][0] + words[1][0]).upcase
  else
    name[0..1].upcase
  end
end

def top_level_directory(path, source_root)
  relative = path.sub("#{source_root}/", "")
  relative.split("/").first
end

# === Content Transformation ===

def build_system_prompt(frontmatter, sections)
  # Start with the intro section (first paragraph after frontmatter)
  intro = sections["_intro"].to_s.strip

  # Clean up the intro: remove bold agent name patterns, strip markdown formatting
  prompt = intro
    .gsub(/You are \*\*[^*]+\*\*,?\s*/, "You are ")
    .gsub(/\*\*([^*]+)\*\*/, '\1')
    .gsub(/\*([^*]+)\*/, '\1')
    .gsub(/^#[^\n]+\n*/, "")
    .strip

  # If intro is too short, supplement from description
  if prompt.length < 50 && frontmatter["description"].present?
    prompt = "You are a #{frontmatter["name"].downcase}. #{frontmatter["description"]}"
  end

  # Trim to a reasonable length
  prompt.truncate(800, omission: "")
end

def build_soul_md(frontmatter, sections)
  parts = []

  # Who You Are
  vibe = frontmatter["vibe"].to_s.strip
  parts << "# Who You Are\n\n_#{vibe}_" if vibe.present?

  # Core Truths from Critical Rules
  rules_section = sections.find { |k, _| k.match?(/critical rules|core rules/i) }&.last
  if rules_section.present?
    rules = extract_rules(rules_section)
    if rules.any?
      parts << "## Core Truths\n\n#{rules.join("\n\n")}"
    end
  end

  # Process / Workflow
  workflow_section = sections.find { |k, _| k.match?(/workflow|process/i) }&.last
  if workflow_section.present?
    cleaned = clean_section(workflow_section)
    parts << "## Your Process\n\n#{cleaned}" if cleaned.present?
  end

  # Core Mission / Capabilities
  mission_section = sections.find { |k, _| k.match?(/core mission|capabilities|core capabilities/i) }&.last
  if mission_section.present?
    cleaned = clean_section(mission_section)
    parts << "## Deliverables\n\n#{cleaned}" if cleaned.present?
  end

  # Success Metrics
  metrics_section = sections.find { |k, _| k.match?(/success metrics|metrics/i) }&.last
  if metrics_section.present?
    cleaned = clean_section(metrics_section)
    parts << "## Success Metrics\n\n#{cleaned}" if cleaned.present?
  end

  # Communication Style
  comm_section = sections.find { |k, _| k.match?(/communication style|communication/i) }&.last
  if comm_section.present?
    cleaned = clean_section(comm_section)
    parts << "## Communication\n\n#{cleaned}" if cleaned.present?
  end

  # Memory
  parts << <<~MEMORY
    ## Your Memory

    You have memories from past sessions. Use them. Check what you've learned before starting work. Update your memories when you learn something worth keeping.
  MEMORY

  # Vibe
  parts << "## Vibe\n\n#{vibe}" if vibe.present?

  parts.join("\n\n")
end

def extract_rules(text)
  rules = []
  current_rule = nil

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?
    # Skip code blocks
    next if stripped.start_with?("```")

    if stripped.start_with?("### ") || stripped.match?(/^[-*]\s+\*\*/)
      rules << current_rule if current_rule.present?
      # Convert ### headers to bold-lead paragraphs
      title = stripped.sub(/^###\s+/, "").sub(/^[-*]\s+/, "").gsub(/\*\*/, "")
      current_rule = "**#{title}.**"
    elsif stripped.start_with?("- ", "* ")
      # Append bullet content to current rule
      content = stripped.sub(/^[-*]\s+/, "").gsub(/\*\*([^*]+)\*\*:?\s*/, "")
      if current_rule
        current_rule += " #{content}"
      else
        current_rule = content
      end
    elsif current_rule
      current_rule += " #{stripped}"
    end
  end
  rules << current_rule if current_rule.present?
  rules.first(6) # Cap at 6 core truths
end

def clean_section(text)
  # Remove code blocks longer than 5 lines
  cleaned = text.gsub(/```[\s\S]*?```/) do |block|
    block.count("\n") > 5 ? "" : block
  end
  # Trim excessive whitespace
  cleaned.gsub(/\n{3,}/, "\n\n").strip.truncate(2000, omission: "\n...")
end

# === Main Import ===

unless Dir.exist?(SOURCE_PATH)
  puts "Community templates source not found at #{SOURCE_PATH}."
  puts "Clone it: git clone --depth 1 https://github.com/msitarzewski/agency-agents.git #{SOURCE_PATH}"
  next
end

puts "Importing community agent templates from #{SOURCE_PATH}..."

imported = 0
skipped = 0

Dir.glob("#{SOURCE_PATH}/**/*.md").sort.each do |path|
  relative = path.sub("#{SOURCE_PATH}/", "")

  # Skip non-agent files
  next if SKIP_DIRS.any? { |d| relative.start_with?("#{d}/") }
  next if %w[README.md CONTRIBUTING.md LICENSE].include?(File.basename(path))

  content = File.read(path)
  frontmatter, body = parse_frontmatter(content)

  name = frontmatter["name"]
  unless name.present?
    skipped += 1
    next
  end

  sections = parse_sections(body)
  dir = top_level_directory(path, SOURCE_PATH)

  category = DIRECTORY_CATEGORY_MAP[dir] || "general"
  tools = DIRECTORY_TOOLS_MAP[dir] || DIRECTORY_TOOLS_MAP["specialized"]
  skills = DIRECTORY_SKILLS_MAP[dir] || []
  model_config = DIRECTORY_MODEL_MAP[dir] || DIRECTORY_MODEL_MAP["specialized"]

  system_prompt = build_system_prompt(frontmatter, sections)
  soul_md = build_soul_md(frontmatter, sections)
  icon = generate_icon(name)
  description = frontmatter["description"].to_s.truncate(500)
  featured = FEATURED_NAMES.include?(name)

  template = AgentTemplate.find_or_initialize_by(name: name)

  # Don't overwrite Hivemind-native templates (v2.0.0+)
  if template.persisted? && template.version.to_s >= "2.0.0" && template.author == "Hivemind"
    skipped += 1
    next
  end

  template.assign_attributes(
    description: description,
    role: name,
    category: category,
    icon: icon,
    featured: featured,
    author: "The Agency (community)",
    version: "1.0.0",
    system_prompt: system_prompt,
    model_config: model_config,
    tools_config: { enabled: tools },
    skills_config: { enabled: skills },
    soul_md: soul_md
  )

  template.save!
  imported += 1
  puts "  ✓ #{name} [#{category}]"
rescue StandardError => e
  puts "  ✗ #{path}: #{e.message}"
  skipped += 1
end

puts "Community templates: #{imported} imported, #{skipped} skipped."
