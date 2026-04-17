# frozen_string_literal: true

require "set"

module Agents
  # Triggers early compaction at logical boundaries (spec success, file
  # edit batches, topic switch) rather than waiting for the hard context
  # limit. Prevents late-session context bloat.
  #
  # Ported from rubyn-code's Context::DecisionCompactor, simplified to
  # call Agents::ContextManager#prune_messages directly.
  class DecisionCompactor
    EARLY_COMPACT_RATIO = 0.6
    STOPWORDS = %w[the and for this that with from have been will your what].to_set.freeze

    attr_reader :pending_trigger

    def initialize(context_manager:, threshold:)
      @context_manager = context_manager
      @threshold = threshold
      @pending_trigger = nil
      @last_topic_keywords = Set.new
      @edited_files = Set.new
    end

    def signal_specs_passed!
      @pending_trigger = :specs_passed
    end

    def signal_file_edited!(path)
      @edited_files << path.to_s
    end

    def signal_edit_batch_complete!
      return unless @edited_files.size > 1
      @pending_trigger = :multi_file_edit_complete
      @edited_files.clear
    end

    def detect_topic_switch(user_message)
      keywords = extract_keywords(user_message)
      overlap = keywords & @last_topic_keywords

      @pending_trigger = :topic_switch if @last_topic_keywords.any? && overlap.empty? && keywords.any?
      @last_topic_keywords = keywords
    end

    # Returns the (possibly-compacted) messages. If no trigger is pending
    # or context is under the threshold ratio, returns messages unchanged.
    def check!(messages)
      return messages unless @pending_trigger

      estimated = @context_manager.estimate_tokens_for(messages)
      return messages unless estimated > (@threshold * EARLY_COMPACT_RATIO)

      trigger = @pending_trigger
      @pending_trigger = nil

      Rails.logger.info("[DecisionCompactor] Early compaction triggered: #{trigger}")
      @context_manager.prune_messages(messages)
    end

    def reset!
      @pending_trigger = nil
      @last_topic_keywords.clear
      @edited_files.clear
    end

    private

    def extract_keywords(text)
      text.to_s.downcase
          .scan(/\b[a-z]{3,}\b/)
          .reject { |w| STOPWORDS.include?(w) }
          .to_set
    end
  end
end
