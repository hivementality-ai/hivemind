# frozen_string_literal: true

module Tools
  # Auto-populates the user model by scanning all active memories and
  # re-categorizing entries that look like user preferences but were stored
  # under a different category (typically "general").
  #
  # Detection is keyword-based. Memories that match preference signals are
  # updated to category: "user_preference". Already-categorized memories
  # are left untouched. A dry_run option lets agents preview what would change
  # before committing.
  #
  # This is a one-shot bootstrapping tool for agents that accumulated memories
  # before Phase 2's structured categorization existed.
  class UserModelPopulateExecutor < BaseExecutor
    # Signals that suggest a memory describes how the user likes things done.
    PREFERENCE_SIGNALS = [
      /\buser\s+(prefer|like|want|expect|always|never|require|hate|dislike)\b/i,
      /\bprefer(s|red)?\b/i,
      /\balways\s+(use|want|prefer|create|open|push|make|do)\b/i,
      /\bnever\s+(use|want|push|commit|mention|do)\b/i,
      /\bstrict\s+rule\b/i,
      /\bzero\s+tolerance\b/i,
      /\bmust\s+(always|never|use|be)\b/i,
      /\bdon'?t\s+(use|push|commit|mention|send)\b/i,
      /\bdo\s+not\s+(use|push|commit|mention|send)\b/i,
      /\bno\s+(mention|use|push)\s+of\b/i,
      /\bexplicitly\s+(wants|requires|prefers|asked)\b/i,
      /\benforces?\b/i,
      /\bonly\s+(prs?|branches?|feature\s+branch)\b/i,
      /\binstruct(ed|ion)\b.*\b(never|always|only|must)\b/i
    ].freeze

    # Categories we'll scan for reclassification candidates.
    SCAN_CATEGORIES = %w[general factual learned_behavior].freeze

    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      dry_run = input["dry_run"] == true || input["dry_run"] == "true"

      candidates = find_candidates
      return no_candidates_response if candidates.empty?

      matches = candidates.select { |entry| preference_signal?(entry.content) }
      return no_matches_response(candidates.size) if matches.empty?

      unless dry_run
        ids = matches.map(&:id)
        MemoryEntry.where(id: ids).update_all(category: "user_preference", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      ServiceResponse.success(data: {
        output: format_result(matches, dry_run: dry_run),
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "User model populate failed: #{e.message}")
    end

    private

    def find_candidates
      MemoryEntry
        .where(agent: agent, category: SCAN_CATEGORIES, status: "active")
        .order(created_at: :asc)
    end

    def preference_signal?(content)
      PREFERENCE_SIGNALS.any? { |pattern| content.match?(pattern) }
    end

    def format_result(matches, dry_run:)
      action = dry_run ? "Would reclassify" : "Reclassified"
      lines  = [ "#{action} #{matches.size} memor#{matches.size == 1 ? 'y' : 'ies'} as user_preference:\n" ]

      matches.each do |entry|
        lines << "- [ID:#{entry.id}] (was: #{entry.category}) #{entry.content.truncate(200)}"
      end

      unless dry_run
        lines << "\nUser model updated. Run `user_model` to view the full structured profile."
      end

      if dry_run
        lines << "\nDry run — no changes made. Call again with dry_run: false to apply."
      end

      lines.join("\n")
    end

    def no_candidates_response
      ServiceResponse.success(data: {
        output: "No memories in scannable categories (#{SCAN_CATEGORIES.join(', ')}) found. " \
                "Nothing to reclassify.",
        exit_code: 0
      })
    end

    def no_matches_response(scanned_count)
      ServiceResponse.success(data: {
        output: "Scanned #{scanned_count} memories — none matched preference signals. " \
                "Your user model may already be well-categorized, or preferences haven't been recorded yet.",
        exit_code: 0
      })
    end
  end
end
