# frozen_string_literal: true

module Reflection
  # Persists reflection insights as `learned_behavior` memories.
  #
  # Maps each reflection section to an appropriate memory type:
  #   key_insights    → procedural  (durable how-to knowledge)
  #   do_differently  → procedural  (behaviour corrections)
  #   went_well       → semantic    (facts about what works)
  #   was_hard        → semantic    (facts about obstacles)
  #   novel_solutions → procedural  (reusable techniques)
  #
  # All memories are stored with category: "learned_behavior" so they are
  # queryable via MemoryEntry.by_category("learned_behavior") and are
  # correctly categorised within the Phase 1 memory system.
  class MemoryPipeline
    SECTION_MAP = {
      "key_insights"    => "procedural",
      "do_differently"  => "procedural",
      "novel_solutions" => "procedural",
      "went_well"       => "semantic",
      "was_hard"        => "semantic"
    }.freeze

    # Importance weights per section — key insights and novel solutions are
    # higher-value than raw observations.
    IMPORTANCE_MAP = {
      "key_insights"    => 0.8,
      "do_differently"  => 0.75,
      "novel_solutions" => 0.85,
      "went_well"       => 0.55,
      "was_hard"        => 0.6
    }.freeze

    def self.call(agent:, task:, reflection:, score: 0.5)
      new(agent: agent, task: task, reflection: reflection, score: score).call
    end

    def initialize(agent:, task:, reflection:, score:)
      @agent      = agent
      @task       = task
      @reflection = reflection
      @score      = score
      @stored     = 0
    end

    def call
      SECTION_MAP.each do |section, memory_type|
        items = Array(@reflection[section]).reject(&:blank?)
        items.each { |item| store_memory(item, memory_type, section) }
      end

      Rails.logger.info("[Reflection::MemoryPipeline] Stored #{@stored} memories for agent=#{@agent.id}")
      @stored
    rescue StandardError => e
      Rails.logger.error("[Reflection::MemoryPipeline] Failed for agent=#{@agent.id}: #{e.message}")
      0
    end

    private

    def store_memory(content, memory_type, section)
      Memory::Store.call(
        agent:        @agent,
        content:      content,
        memory_type:  memory_type,
        importance:   IMPORTANCE_MAP.fetch(section, 0.6),
        metadata:     build_metadata(section),
        category:     "learned_behavior",
        async:        true
      )
      @stored += 1
    end

    def build_metadata(section)
      meta = {
        "source"             => "post_task_reflection",
        "reflection_section" => section,
        "reflection_score"   => @score,
        "reflected_at"       => Time.current.iso8601
      }
      meta["task_id"]    = @task.id    if @task
      meta["task_title"] = @task.title if @task
      meta
    end
  end
end
