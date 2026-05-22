# frozen_string_literal: true

module Reflection
  # Converts novel solutions from a post-task reflection into skill proposals.
  #
  # When a reflection surfaces one or more novel_solutions, this pipeline
  # packages them into a draft skill proposal and routes it through the
  # Phase 4 Agents::SkillCreator pipeline (validation → security scan →
  # pending admin approval).
  #
  # One proposal is generated per reflection batch — multiple novel solutions
  # are combined into a single skill rather than creating N micro-skills.
  # This avoids polluting the proposal queue with fragmented skills.
  #
  # The skill is named deterministically from the task title + timestamp
  # so that a re-run of the same reflection does not create duplicates
  # (SkillCreator rejects existing names).
  class SkillProposalPipeline
    MIN_NOVEL_SOLUTIONS = 1
    MIN_SOLUTION_LENGTH = 20  # chars — filters out "Used git" type noise

    def self.call(agent:, task:, reflection:)
      new(agent: agent, task: task, reflection: reflection).call
    end

    def initialize(agent:, task:, reflection:)
      @agent      = agent
      @task       = task
      @reflection = reflection
    end

    def call
      solutions = extract_novel_solutions
      return unless solutions.size >= MIN_NOVEL_SOLUTIONS

      result = Agents::SkillCreator.call(
        agent:          @agent,
        name:           skill_name,
        summary:        skill_summary(solutions),
        content:        build_skill_content(solutions),
        category:       "utilities",
        share_with_team: false
      )

      if result.success?
        Rails.logger.info("[Reflection::SkillProposalPipeline] Proposed skill '#{skill_name}' for agent=#{@agent.id}")
      else
        Rails.logger.warn("[Reflection::SkillProposalPipeline] Skill proposal rejected: #{result.error}")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Reflection::SkillProposalPipeline] Failed for agent=#{@agent.id}: #{e.message}")
      nil
    end

    private

    def extract_novel_solutions
      Array(@reflection["novel_solutions"])
        .reject(&:blank?)
        .select { |s| s.length >= MIN_SOLUTION_LENGTH }
    end

    # Deterministic name derived from task or timestamp.
    def skill_name
      @skill_name ||= begin
        base = if @task&.title.present?
          @task.title
            .downcase
            .gsub(/[^a-z0-9\s]/, "")
            .strip
            .split
            .first(5)
            .join("_")
        else
          "reflection"
        end
        timestamp = Time.current.strftime("%Y%m%d")
        "#{base}_#{timestamp}"[0, 60]
      end
    end

    def skill_summary(solutions)
      "Patterns learned from #{@task&.title.presence || "a completed task"}: #{solutions.first.truncate(100)}"
        .truncate(150)
    end

    def build_skill_content(solutions)
      task_context = if @task
        "**Task:** #{@task.title}"
      else
        "**Source:** post-task reflection"
      end

      insight_lines = solutions.each_with_index.map do |s, i|
        "#{i + 1}. #{s}"
      end

      key_insights = Array(@reflection["key_insights"]).reject(&:blank?)
      insight_section = key_insights.any? ? "\n## Key Insights\n\n#{key_insights.map { |i| "- #{i}" }.join("\n")}" : ""

      <<~MARKDOWN
        ## Overview

        #{task_context}

        This skill captures novel techniques and patterns discovered during task execution.
        Apply these approaches when facing similar problems in the future.

        ## Novel Solutions

        #{insight_lines.join("\n")}
        #{insight_section}

        ## When to Use

        Load this skill when working on tasks that involve similar patterns to:
        #{@task&.title.presence || "the originating task"}.
      MARKDOWN
    end
  end
end
