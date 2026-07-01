# frozen_string_literal: true

module Skills
  # Implements the 3-tier skill loading system.
  #
  # Tiers:
  #   core        — Always loaded. Content injected directly into system prompt via
  #                 role_instructions.rb. No per-request analytics needed.
  #   contextual  — Auto-loaded when relevance score >= threshold. Content injected
  #                 dynamically per request by Sessions::MessageBuilder.
  #   manual      — On-demand only. Agent must call load_skill explicitly.
  #
  # Usage (full — returns all tiers, used for standalone calls):
  #   result = Skills::AutoLoader.call(agent: agent, session: session, context: user_message)
  #   result[:core_skills]       # => [Skill, ...]  always loaded
  #   result[:contextual_skills] # => [Skill, ...]  loaded due to relevance
  #   result[:prompt_blocks]     # => [String, ...]  content blocks to inject
  #
  # Usage (contextual only — used from MessageBuilder per request):
  #   result = Skills::AutoLoader.call(agent: agent, session: session, context: user_message,
  #                                    contextual_only: true)
  #
  # Analytics:
  #   Core skill loads are recorded once per session start.
  #   Contextual loads are recorded each time they are auto-injected.
  class AutoLoader
    DEFAULT_RELEVANCE_THRESHOLD = 0.3
    MAX_CONTEXTUAL_SKILLS       = 3    # cap auto-injected skills to avoid prompt bloat

    def self.call(agent:, session: nil, context: nil, contextual_only: false)
      new(agent: agent, session: session, context: context, contextual_only: contextual_only).call
    end

    def initialize(agent:, session: nil, context: nil, contextual_only: false)
      @agent            = agent
      @session          = session
      @context          = context.to_s
      @contextual_only  = contextual_only
    end

    def call
      enabled_skills = @agent.skills.enabled.to_a

      core_skills = @contextual_only ? [] : load_core(enabled_skills)
      contextual_skills = load_contextual(enabled_skills, exclude: core_skills)

      all_loaded = core_skills + contextual_skills

      record_events(core_skills, tier: "core") unless @contextual_only
      record_contextual_events(contextual_skills)

      {
        core_skills: core_skills,
        contextual_skills: contextual_skills,
        prompt_blocks: build_prompt_blocks(core_skills, contextual_skills),
        manual_skills: enabled_skills - all_loaded
      }
    end

    private

    def load_core(skills)
      skills.select { |s| s.tier == "core" }
    end

    def load_contextual(skills, exclude:)
      return [] if @context.blank?

      candidates = skills.select { |s| s.tier == "contextual" } - exclude

      ranked = Skills::RelevanceScorer.rank(
        skills: candidates,
        context: @context,
        threshold: DEFAULT_RELEVANCE_THRESHOLD
      )

      @ranked_contextual = ranked  # retain scores for event recording

      ranked.first(MAX_CONTEXTUAL_SKILLS).map { |r| r[:skill] }
    end

    def build_prompt_blocks(core_skills, contextual_skills)
      blocks = []

      if core_skills.any?
        blocks << format_skill_block("Core Skills (always active)", core_skills)
      end

      if contextual_skills.any?
        blocks << format_skill_block("Contextual Skills (loaded for this task)", contextual_skills)
      end

      blocks
    end

    def format_skill_block(heading, skills)
      lines = [ "## #{heading}" ]
      skills.each do |skill|
        lines << "### #{skill.name}"
        lines << skill.content
        lines << ""
      end
      lines.join("\n")
    end

    def record_events(skills, tier:)
      skills.each do |skill|
        SkillLoadEvent.create!(
          skill: skill,
          agent: @agent,
          session: @session,
          load_tier: tier,
          relevance_score: nil,
          trigger_context: nil
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[Skills::AutoLoader] Failed to record #{tier} event for skill #{skill.id}: #{e.message}")
      end
    end

    def record_contextual_events(skills)
      return if skills.empty?

      ranked_map = (@ranked_contextual || []).each_with_object({}) do |r, h|
        h[r[:skill].id] = r[:score]
      end

      context_snippet = @context.truncate(500)

      skills.each do |skill|
        SkillLoadEvent.create!(
          skill: skill,
          agent: @agent,
          session: @session,
          load_tier: "contextual",
          relevance_score: ranked_map[skill.id],
          trigger_context: context_snippet
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[Skills::AutoLoader] Failed to record contextual event for skill #{skill.id}: #{e.message}")
      end
    end
  end
end
