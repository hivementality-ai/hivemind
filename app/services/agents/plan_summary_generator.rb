# frozen_string_literal: true

module Agents
  class PlanSummaryGenerator
    def self.call(session:, agent: nil)
      new(session: session, agent: agent).call
    end

    def initialize(session:, agent: nil)
      @session = session
      @agent = agent
    end

    def call
      plan = @session.metadata&.dig("current_plan")
      unless plan.present?
        return ServiceResponse.failure(error: "No plan available to summarize")
      end

      # Build execution summary from transcript
      execution_summary = build_execution_summary(plan)

      # Generate markdown document
      markdown = generate_markdown(plan, execution_summary)

      # Extract key learnings from conversation
      learnings = extract_learnings(plan, execution_summary)

      ServiceResponse.success(data: {
        summary: execution_summary,
        markdown: markdown,
        learnings: learnings,
        plan: plan,
        generated_at: Time.current.iso8601
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Summary generation failed: #{e.message}")
    end

    private

    def build_execution_summary(plan)
      transcript = @session.transcript || []
      
      summary = {
        "original_task" => extract_task_from_transcript,
        "plan_generated_at" => @session.metadata&.dig("plan_generated_at"),
        "plan_started_at" => @session.metadata&.dig("plan_started_at"),
        "plan_completed_at" => Time.current.iso8601,
        "phases_completed" => @session.metadata&.dig("current_phase") || 0,
        "total_phases" => plan["phases"]&.length || 0,
        "phase_outcomes" => extract_phase_outcomes(plan, transcript),
        "key_results" => extract_key_results(transcript),
        "duration" => calculate_duration
      }

      summary
    end

    def extract_task_from_transcript
      transcript = @session.transcript || []
      
      # Find the original #plan command
      transcript.each do |entry|
        if entry["content"]&.include?("#plan")
          content = entry["content"].gsub(/#plan\s*/, "").strip
          return content.present? ? content : "Plan creation task"
        end
      end
      
      "Plan creation task"
    end

    def extract_phase_outcomes(plan, transcript)
      outcomes = {}
      
      plan["phases"]&.each do |phase|
        phase_num = phase["number"]
        phase_name = phase["name"]
        
        # Look for phase markers in transcript
        phase_content = find_phase_content(phase_num, phase_name, transcript)
        
        outcomes[phase_num.to_s] = {
          "phase_number" => phase_num,
          "phase_name" => phase_name,
          "objectives" => phase["objectives"],
          "status" => phase_content.present? ? "completed" : "planned",
          "summary" => phase_content.present? ? generate_phase_summary(phase_content) : nil
        }
      end
      
      outcomes
    end

    def find_phase_content(phase_num, phase_name, transcript)
      transcript_text = transcript.map { |e| e["content"].to_s }.join("\n")
      
      # Look for phase markers like "## Phase N:" or "Phase N:"
      pattern = /##?\s*Phase\s*#{phase_num}[:\s]/i
      
      if transcript_text.match?(pattern)
        # Extract content between this phase and next phase or end
        start_idx = transcript_text.index(pattern)
        next_phase_idx = transcript_text.index(/##?\s*Phase\s*#{phase_num + 1}/i, start_idx)
        
        if next_phase_idx
          transcript_text[start_idx...next_phase_idx]
        else
          transcript_text[start_idx..-1]
        end
      else
        nil
      end
    end

    def generate_phase_summary(content)
      # Extract meaningful summary from phase content
      lines = content.split("\n").reject(&:blank?)
      
      # Take first few substantial lines (avoid markers)
      summary_lines = lines.reject { |l| l.match?(/^#+\s*Phase/) }.first(3)
      summary_lines.join(" ").truncate(200)
    end

    def extract_key_results(transcript)
      results = []
      transcript_text = transcript.map { |e| e["content"].to_s }.join("\n")
      
      # Look for completion markers and success indicators
      completion_patterns = [
        /✅|✓|complete|done|finished|ready|implemented/i,
        /success|working|functioning|deployed|released/i,
        /created|built|added|integrated|configured/i
      ]
      
      lines = transcript_text.split("\n")
      lines.each do |line|
        if completion_patterns.any? { |p| line.match?(p) }
          cleaned = line.gsub(/^#+\s*/, "").strip
          results << cleaned if cleaned.present? && results.length < 5
        end
      end
      
      results
    end

    def extract_learnings(plan, execution_summary)
      learnings = []
      
      # Extract from transcript
      transcript = @session.transcript || []
      transcript_text = transcript.map { |e| e["content"].to_s }.join("\n")
      
      # Look for learning indicators
      if transcript_text.match?(/learned|discovered|found that|realized|encountered/i)
        learnings << "Plan execution revealed new insights and challenges"
      end
      
      # Check if all phases were completed
      if execution_summary["phases_completed"] == execution_summary["total_phases"]
        learnings << "Successfully completed all planned phases"
      elsif execution_summary["phases_completed"] > 0
        learnings << "Partially completed plan - #{execution_summary['phases_completed']} of #{execution_summary['total_phases']} phases finished"
      end
      
      # Estimate efficiency
      duration = calculate_duration
      if plan["estimated_duration"].present?
        learnings << "Plan execution duration: #{duration}"
      end
      
      learnings
    end

    def calculate_duration
      started_at = @session.metadata&.dig("plan_started_at")
      completed_at = Time.current
      
      if started_at.present?
        begin
          start_time = Time.parse(started_at)
          duration_seconds = (completed_at - start_time).round
          
          if duration_seconds < 60
            "#{duration_seconds} seconds"
          elsif duration_seconds < 3600
            "#{(duration_seconds / 60).round} minutes"
          else
            hours = (duration_seconds / 3600).round(1)
            "#{hours} hours"
          end
        rescue StandardError
          "unknown"
        end
      else
        "not tracked"
      end
    end

    def generate_markdown(plan, execution_summary)
      task = execution_summary["original_task"]
      timestamp = execution_summary["plan_completed_at"]
      
      lines = []
      
      # Title
      lines << "# Plan Summary: #{task}"
      lines << ""
      lines << "**Generated:** #{Time.parse(timestamp).strftime('%B %d, %Y at %I:%M %p')}"
      lines << ""
      
      # Execution Status
      phases_completed = execution_summary["phases_completed"]
      total_phases = execution_summary["total_phases"]
      status = if phases_completed == total_phases
                 "✅ COMPLETED"
               elsif phases_completed > 0
                 "⏸️ PARTIALLY COMPLETED"
               else
                 "⏭️ STARTED"
               end
      
      lines << "## Execution Status"
      lines << "#{status} — #{phases_completed}/#{total_phases} phases completed"
      lines << "**Duration:** #{execution_summary['duration']}"
      lines << ""
      
      # Original Plan
      lines << "## Original Plan"
      lines << ""
      lines << "**Overview:** #{plan['overview']}"
      lines << "**Context:** #{plan['context']}"
      lines << "**Estimated Duration:** #{plan['estimated_duration']}"
      lines << ""
      
      lines << "### Planned Phases"
      plan["phases"]&.each do |phase|
        lines << ""
        lines << "**Phase #{phase['number']}: #{phase['name']}**"
        lines << "- *Objectives:* #{phase['objectives'].join('; ')}"
        lines << "- *Approach:* #{phase['approach']}"
        lines << "- *Tools:* #{phase['tools_needed'].join(', ')}"
        lines << "- *Expected Output:* #{phase['expected_output']}"
      end
      lines << ""
      
      # Execution Summary
      lines << "## Execution Summary"
      lines << ""
      
      execution_summary["phase_outcomes"]&.each do |phase_num, outcome|
        lines << "### Phase #{outcome['phase_number']}: #{outcome['phase_name']}"
        lines << "**Status:** #{outcome['status'].upcase}"
        
        if outcome["summary"].present?
          lines << ""
          lines << "**Summary:**"
          lines << outcome["summary"]
        end
        
        lines << ""
      end
      
      # Key Results
      if execution_summary["key_results"].any?
        lines << "## Key Results"
        lines << ""
        execution_summary["key_results"].each do |result|
          lines << "- #{result}"
        end
        lines << ""
      end
      
      # Success Criteria
      if plan["success_criteria"].present?
        lines << "## Success Criteria"
        lines << ""
        plan["success_criteria"].each do |criterion|
          lines << "- #{criterion}"
        end
        lines << ""
      end
      
      # Learnings & Notes
      lines << "## Learnings & Insights"
      lines << ""
      
      learnings = extract_learnings(plan, execution_summary)
      if learnings.any?
        learnings.each { |learning| lines << "- #{learning}" }
      else
        lines << "- Plan execution was completed as designed"
      end
      
      lines << ""
      lines << "---"
      lines << ""
      lines << "*This plan summary was automatically generated by Hivemind.*"
      lines << "**Session ID:** #{@session.id}"
      lines << "**Agent:** #{@agent&.name || 'Unknown'}"
      
      lines.join("\n")
    end
  end
end
