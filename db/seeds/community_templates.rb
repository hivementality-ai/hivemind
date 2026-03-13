# frozen_string_literal: true

# Community Agent Templates
# Imports agent templates from msitarzewski/agency-agents (MIT licensed).
# Source: https://github.com/msitarzewski/agency-agents
#
# The source content is parsed, restructured into Hivemind's soul_md format,
# and rewritten to match our voice. Domain knowledge (specific standards,
# techniques, metrics, workflows) is preserved — the voice becomes ours.
#
# Usage:
#   git clone --depth 1 https://github.com/msitarzewski/agency-agents.git /tmp/agency-agents
#   rails db:seed
#
# Set AGENCY_AGENTS_PATH to override the default clone location.

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
#
# These functions rewrite agency-agents content into Hivemind's voice.
# The structure, domain knowledge, and specifics are preserved —
# the framing and tone become ours.

def strip_code_blocks(text)
  # Remove code blocks >10 lines, keep short inline examples
  text.gsub(/```[a-z]*\n[\s\S]*?```/) do |block|
    block.count("\n") > 10 ? "" : block
  end
end

def build_system_prompt(frontmatter, _sections = nil)
  name = frontmatter["name"].to_s
  description = frontmatter["description"].to_s.strip
  vibe = frontmatter["vibe"].to_s.strip

  # Build expertise description: strip role name variants from the beginning
  # to avoid "You are a frontend developer. Frontend developer specializing in..."
  name_words = name.downcase.split(/[\s\-]+/)
  expertise = description
    .sub(/^#{Regexp.escape(name)}\s*/i, "")           # "Frontend Developer specializing" → "specializing"
    .sub(/^Expert\s+#{Regexp.escape(name)}\s*/i, "")   # "Expert Frontend Developer spec" → "spec"
    .sub(/^Senior\s+#{Regexp.escape(name)}\s*/i, "")   # "Senior Frontend Developer spec" → "spec"
    .gsub(/^Expert |^Senior |^Specialized |^Advanced /, "")
    .sub(/^#{name_words.join('\s+')}[\s,]*/i, "")      # Last-resort fuzzy strip
    .sub(/^[a-z]/) { |c| c.upcase }
    .sub(/\.\s*$/, "") # Strip trailing period — we add our own

  # Fix sentence fragments: "Specializing in..." → "You specialize in..."
  expertise = expertise
    .sub(/^Specializing\s+/i, "You specialize ")
    .sub(/^Focused\s+/i, "You focus ")
    .sub(/^Transforms?\s+/i, "You transform ")
    .sub(/^Creates?\s+/i, "You create ")
    .sub(/^Builds?\s+/i, "You build ")

  # If stripping removed too much, fall back to full description
  expertise = description.sub(/\.\s*$/, "") if expertise.length < 20

  # Construct system_prompt in Hivemind's voice:
  # Direct, opinionated, no bold markdown, personality-forward
  name_lower = name.downcase
  # Correct article: "a" vs "an" — check the spoken sound of the first word
  first_word = name_lower.split(/[\s\-]/).first
  article = first_word.match?(/^(ai|a[eiou]|an|un|e[a-z]|in|ob|op|or|ar|im|ul)/i) ? "an" : "a"

  prompt = "You are #{article} #{name_lower}. #{expertise}."

  # Add vibe as personality if available — but skip if it duplicates the description
  if vibe.present? && vibe.length > 10
    # Check for overlap: if vibe shares >50% of words with what's already in prompt, skip it
    vibe_words = vibe.downcase.scan(/\w+/)
    prompt_words = prompt.downcase.scan(/\w+/)
    overlap = (vibe_words & prompt_words).length.to_f / [vibe_words.length, 1].max
    unless overlap > 0.5
      vibe_clean = vibe.sub(/\.\s*$/, "")
      prompt += " #{vibe_clean}."
    end
  end

  prompt.gsub(/\s+/, " ").strip.truncate(800, omission: "")
end

def build_soul_md(frontmatter, sections)
  parts = []
  vibe = frontmatter["vibe"].to_s.strip
  name = frontmatter["name"].to_s

  # === Who You Are ===
  # Rewrite the vibe into Hivemind's italic soul statement
  if vibe.present?
    parts << "# Who You Are\n\n_#{vibe}_"
  elsif frontmatter["description"].present?
    parts << "# Who You Are\n\n_#{frontmatter["description"].truncate(120, omission: ".")}_"
  end

  # === Core Truths ===
  # Extract from Critical Rules and rewrite as bold-lead paragraphs.
  # Fall back to Core Capabilities for agents that don't have a rules section.
  has_dedicated_rules = false
  rules_section = sections.find { |k, _| k.match?(/critical rules|core rules/i) }&.last
  if rules_section.present?
    has_dedicated_rules = true
  else
    rules_section = sections.find { |k, _| k.match?(/core capabilities|specialized skills/i) }&.last
  end
  if rules_section.present?
    truths = extract_core_truths(rules_section)
    parts << "## Core Truths\n\n#{truths.join("\n\n")}" if truths.any?
  end

  # === Your Process ===
  # Rewrite workflow into numbered steps with personality
  workflow_section = sections.find { |k, _| k.match?(/workflow|process/i) }&.last
  if workflow_section.present?
    process = rewrite_process(workflow_section)
    parts << "## Your Process\n\n#{process}" if process.present?
  end

  # === Deliverables ===
  # Extract from Core Mission / Capabilities / Technical Deliverables, strip code.
  # Skip capabilities if we already used them for Core Truths (no dedicated rules section).
  deliverables_pattern = if has_dedicated_rules
    /core mission|capabilities|core capabilities|deliverables|what you can do/i
  else
    /core mission|deliverables|what you can do/i
  end
  mission_section = sections.find { |k, _| k.match?(deliverables_pattern) }&.last
  if mission_section.present?
    deliverables = rewrite_deliverables(mission_section)
    parts << "## Deliverables\n\n#{deliverables}" if deliverables.present?
  end

  # === Success Metrics ===
  metrics_section = sections.find { |k, _| k.match?(/success metrics|metrics/i) }&.last
  if metrics_section.present?
    metrics = rewrite_metrics(metrics_section)
    parts << "## Success Metrics\n\n#{metrics}" if metrics.present?
  end

  # === Your Memory ===
  # Pull relevant context from the source Identity section and weave into
  # Hivemind's standard memory block
  identity_section = sections.find { |k, _| k.match?(/identity|memory|learning/i) }&.last
  memory_context = extract_memory_context(identity_section, name)
  parts << <<~MEMORY.strip
    ## Your Memory

    #{memory_context}Use your memories from past sessions. Check what you've learned before starting work. Update your memories when you learn something worth keeping.
  MEMORY

  # === Communication ===
  comm_section = sections.find { |k, _| k.match?(/communication style|communication/i) }&.last
  if comm_section.present?
    comm = rewrite_communication(comm_section)
    parts << "## Communication\n\n#{comm}" if comm.present?
  end

  # === Vibe ===
  parts << "## Vibe\n\n#{vibe}" if vibe.present?

  parts.join("\n\n")
end

# Rewrite critical rules into Hivemind bold-lead paragraph style.
# Source format: ### headers or bullet points with bold labels
# Target format: **Opinionated short phrase.** Explanation with domain specifics.
def extract_core_truths(text)
  text = strip_code_blocks(text)
  truths = []
  current_title = nil
  current_body_lines = []

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    if stripped.start_with?("### ")
      # Flush previous truth
      if current_title
        truths << format_truth(current_title, current_body_lines.join(" "))
      end
      current_title = stripped.sub(/^###\s+/, "").strip
      current_body_lines = []
    elsif stripped.match?(/^\*\*[^*]+\*\*$/) || stripped.match?(/^[-*]\s+\*\*[^*]+\*\*\s*$/)
      # Bold-only line = new truth title
      if current_title
        truths << format_truth(current_title, current_body_lines.join(" "))
      end
      current_title = stripped.gsub(/\*\*/, "").sub(/^[-*]\s+/, "").strip
      current_body_lines = []
    elsif stripped.start_with?("- ", "* ")
      content = stripped.sub(/^[-*]\s+/, "")
      # Check for bold-lead bullet: **Title**: description
      if content.match?(/^\*\*[^*]+\*\*:?\s+/)
        if current_title
          truths << format_truth(current_title, current_body_lines.join(" "))
        end
        title_match = content.match(/^\*\*([^*]+)\*\*:?\s*(.*)/)
        current_title = title_match[1].strip
        current_body_lines = [title_match[2].strip].reject(&:empty?)
      else
        # Regular bullet — append to current truth's body
        current_body_lines << content.gsub(/\*\*([^*]+)\*\*/, '\1')
      end
    elsif current_title
      current_body_lines << stripped.gsub(/\*\*([^*]+)\*\*/, '\1')
    end
  end

  # Flush last truth
  truths << format_truth(current_title, current_body_lines.join(" ")) if current_title

  truths.first(6)
end

# Format a single Core Truth in Hivemind's bold-lead style
def format_truth(title, body)
  # Clean up the title: strip trailing periods, make it punchy
  title = title.sub(/\.\s*$/, "").strip

  # Clean up the body: collapse whitespace, strip stray markdown
  body = body
    .gsub(/\*\*([^*]+)\*\*/, '\1')
    .gsub(/\*([^*]+)\*/, '\1')
    .gsub(/\s+/, " ")
    .strip

  if body.present?
    "**#{title}.** #{body.truncate(400, omission: "")}"
  else
    "**#{title}.**"
  end
end

# Rewrite workflow section: keep numbered steps and domain specifics,
# strip verbose explanations and code blocks
def rewrite_process(text)
  text = strip_code_blocks(text)
  lines = []
  step_num = 0

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    # Skip ### sub-headers but keep their content
    if stripped.start_with?("### ")
      step_num += 1
      title = stripped.sub(/^###\s+/, "")
        .gsub(/\*\*([^*]+)\*\*/, '\1')
        .gsub(/^\d+\.\s*/, "")
        .strip
      lines << "#{step_num}. #{title}"
    elsif stripped.match?(/^\d+\.\s+/)
      step_num += 1
      content = stripped.sub(/^\d+\.\s+/, "")
        .gsub(/\*\*([^*]+)\*\*/, '\1')
        .strip
      lines << "#{step_num}. #{content}"
    elsif stripped.start_with?("- ", "* ")
      content = stripped.sub(/^[-*]\s+/, "")
        .gsub(/\*\*([^*]+)\*\*:?\s*/, "")
        .strip
      lines << "   - #{content}" if content.length > 5
    end
  end

  result = lines.join("\n")
  result.truncate(1500, omission: "\n")
end

# Rewrite deliverables: extract key capabilities, strip code blocks,
# convert ### sub-sections to bold-lead descriptions
def rewrite_deliverables(text)
  text = strip_code_blocks(text)
  items = []
  current_item = nil

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    if stripped.start_with?("### ")
      items << current_item if current_item.present?
      title = stripped.sub(/^###\s+/, "").gsub(/\*\*([^*]+)\*\*/, '\1').strip
      current_item = "**#{title}**"
    elsif stripped.start_with?("- ", "* ")
      content = stripped.sub(/^[-*]\s+/, "")
      # Extract bold-lead items
      if content.match?(/^\*\*[^*]+\*\*:?\s+/)
        items << current_item if current_item.present?
        match = content.match(/^\*\*([^*]+)\*\*:?\s*(.*)/)
        desc = match[2].strip
        current_item = desc.present? ? "**#{match[1]}**: #{desc}" : "**#{match[1]}**"
      else
        # Regular bullet — append as sub-detail
        clean = content.gsub(/\*\*([^*]+)\*\*/, '\1').strip
        current_item = "#{current_item}\n- #{clean}" if current_item && clean.length > 5
      end
    elsif stripped.match?(/^\*\*[^*]+\*\*:?\s+/) && !stripped.start_with?("#")
      items << current_item if current_item.present?
      match = stripped.match(/^\*\*([^*]+)\*\*:?\s*(.*)/)
      desc = match[2].to_s.strip
      current_item = desc.present? ? "**#{match[1]}**: #{desc}" : "**#{match[1]}**"
    end
  end

  items << current_item if current_item.present?

  result = items.first(8).join("\n\n")
  result.truncate(2000, omission: "\n")
end

# Rewrite metrics: keep specific numbers, KPIs, and targets
def rewrite_metrics(text)
  text = strip_code_blocks(text)
  metrics = []

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?

    if stripped.start_with?("### ")
      title = stripped.sub(/^###\s+/, "").gsub(/\*\*([^*]+)\*\*/, '\1').strip
      metrics << "**#{title}**"
    elsif stripped.start_with?("- ", "* ")
      content = stripped.sub(/^[-*]\s+/, "")
        .gsub(/\*\*([^*]+)\*\*/, '\1')
        .strip
      metrics << "- #{content}" if content.length > 5
    end
  end

  result = metrics.join("\n")
  result.truncate(1500, omission: "\n")
end

# Extract memory-relevant context from the Identity section
def extract_memory_context(identity_text, _name = nil)
  return "" unless identity_text.present?

  # Look for Memory or Experience lines
  memory_line = nil
  experience_line = nil

  identity_text.each_line do |line|
    stripped = line.strip
    if stripped.match?(/\*\*Memory\*\*:?\s*/i)
      memory_line = stripped.sub(/.*\*\*Memory\*\*:?\s*/i, "").strip
    elsif stripped.match?(/\*\*Experience\*\*:?\s*/i)
      experience_line = stripped.sub(/.*\*\*Experience\*\*:?\s*/i, "").strip
    end
  end

  context = ""
  if memory_line.present?
    # Rewrite from third-person source to second-person Hivemind
    context = memory_line
      .sub(/^You remember\s+/i, "You remember ")
      .sub(/^You have\s+/i, "You have ")
      .strip
    context = "You remember #{context}" unless context.start_with?("You ")
    context += ". " unless context.end_with?(".")
    context += " "
  elsif experience_line.present?
    context = experience_line.strip
    context += ". " unless context.end_with?(".")
    context += " "
  end

  context
end

# Rewrite communication style into concise personality description
def rewrite_communication(text)
  text = strip_code_blocks(text)
  lines = []

  text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?
    next if stripped.start_with?("### ", "# ")

    if stripped.start_with?("- ", "* ")
      content = stripped.sub(/^[-*]\s+/, "")
        .gsub(/\*\*([^*]+)\*\*:?\s*/, "")
        .strip
      lines << "- #{content}" if content.length > 10
    end
  end

  lines.first(6).join("\n")
end

# === Main Import ===

if Dir.exist?(SOURCE_PATH)
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
      author: "Hivemind",
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
else
  puts "Community templates source not found at #{SOURCE_PATH}."
  puts "Clone it: git clone --depth 1 https://github.com/msitarzewski/agency-agents.git #{SOURCE_PATH}"
end
