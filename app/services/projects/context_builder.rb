# frozen_string_literal: true

module Projects
  class ContextBuilder
    def self.call(milestone:, resume: false)
      new(milestone: milestone, resume: resume).call
    end

    def initialize(milestone:, resume:)
      @milestone = milestone
      @resume = resume
    end

    def call
      @resume ? build_resume_context : build_initial_context
    end

    private

    def build_initial_context
      parts = []
      parts << "## Project: #{@milestone.project.title}"
      parts << @milestone.project.description.to_s.truncate(500)
      parts << ""
      parts << "### Your Milestone: #{@milestone.title}"
      parts << @milestone.description.to_s
      parts << ""
      parts << "### Acceptance Criteria"
      parts << @milestone.acceptance_criteria.to_s
      parts << ""

      completed_deps = ProjectMilestone.where(id: @milestone.depends_on, status: "completed")
      if completed_deps.any?
        parts << "### Completed Upstream Work"
        completed_deps.each { |m| parts << "- #{m.title}: #{m.agent_notes.to_s.truncate(200)}" }
        parts << ""
      end

      siblings = @milestone.project.milestones.where.not(id: @milestone.id)
      if siblings.any?
        parts << "### Project Status"
        siblings.ordered.each { |m| parts << "- #{m.title} [#{m.status}]" }
        parts << ""
      end

      memories = recall_project_memories
      if memories.any?
        parts << "### Relevant Memories"
        memories.each { |m| parts << "- #{m.content.truncate(200)}" }
        parts << ""
      end

      if @milestone.review_notes.present? && @milestone.retry_count > 0
        parts << "### User Feedback (Revision #{@milestone.retry_count})"
        parts << @milestone.review_notes
        parts << ""
      end

      parts << "---"
      parts << "When finished, use the project_update tool to submit for review."
      parts.join("\n")
    end

    def build_resume_context
      checkpoint = @milestone.checkpoint

      parts = []
      parts << "## RESUMING MILESTONE (Context Reset Recovery)"
      parts << ""
      parts << "Your previous session was interrupted. Here's where you left off:"
      parts << ""
      parts << "### Project: #{@milestone.project.title}"
      parts << @milestone.project.description.to_s.truncate(500)
      parts << ""
      parts << "### Your Milestone: #{@milestone.title}"
      parts << @milestone.description.to_s
      parts << ""
      parts << "### Acceptance Criteria"
      parts << @milestone.acceptance_criteria.to_s
      parts << ""

      if checkpoint.present?
        parts << "### What You Already Completed"
        (checkpoint["completed_steps"] || []).each { |s| parts << "- #{s}" }
        parts << ""
        parts << "### What Still Needs To Be Done"
        (checkpoint["pending_steps"] || []).each { |s| parts << "- #{s}" }
        parts << ""

        if checkpoint["intermediate_results"].present?
          parts << "### Intermediate Results"
          checkpoint["intermediate_results"].each { |k, v| parts << "- #{k}: #{v}" }
          parts << ""
        end

        if checkpoint["context_notes"].present?
          parts << "### Context Notes"
          parts << checkpoint["context_notes"]
          parts << ""
        end
      end

      if @milestone.session&.try(:conversation_summary).present?
        parts << "### Previous Session Summary"
        parts << @milestone.session.conversation_summary
        parts << ""
      end

      memories = recall_project_memories
      if memories.any?
        parts << "### Relevant Memories from This Project"
        memories.each { |m| parts << "- #{m.content.truncate(200)}" }
        parts << ""
      end

      if @milestone.review_notes.present?
        parts << "### User Feedback (from previous review)"
        parts << @milestone.review_notes
        parts << ""
      end

      parts << "---"
      parts << "Continue from where you left off. Do NOT repeat completed work."
      parts << "When finished, use the project_update tool to mark this milestone as needs_review."
      parts.join("\n")
    end

    def recall_project_memories
      agent = @milestone.agent
      return [] unless agent

      MemoryEntry.where(agent: agent)
                 .where("metadata->>'project_id' = ?", @milestone.project_id.to_s)
                 .order(importance: :desc)
                 .limit(5)
    rescue StandardError
      []
    end
  end
end
