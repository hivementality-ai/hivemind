# frozen_string_literal: true

module HashtagActions
  module Actions
    # User-triggered context compaction. Usage:
    #   #compact                     — summarize the whole session
    #   #compact keep the migration  — summarize with a focus hint
    #
    # Replaces session.transcript with a single compacted message.
    # Original transcript is preserved in session.metadata as a
    # `pre_compact_transcripts` array (latest last) for recoverability.
    class Compact < Base
      def execute
        transcript = session.transcript.to_a
        return { response: "Nothing to compact — session is empty.", status: "empty" } if transcript.empty?

        llm_messages = transcript.map { |entry| entry.slice("role", "content") }
        compacted = Agents::ManualCompact.call(llm_messages, agent: agent, focus: payload.presence)

        if compacted.blank?
          return { response: "Couldn't compact right now — is an Anthropic provider configured?", status: "failed" }
        end

        preserve_original!(transcript)
        session.update!(
          transcript: compacted.map { |m| m.merge("timestamp" => Time.current.iso8601, "source" => "compact_action") }
        )

        summary_text = compacted.first["content"].to_s
        {
          response: "✓ Session compacted (#{transcript.size} → 1 message).\n\n#{summary_text}",
          bypass: true,
          status: "compacted"
        }
      rescue StandardError => e
        Rails.logger.error("[HashtagActions::Compact] Failed: #{e.class}: #{e.message}")
        { response: "Compaction failed: #{e.message}", status: "error" }
      end

      private

      def preserve_original!(transcript)
        metadata = session.metadata.to_h
        backups = metadata["pre_compact_transcripts"] || []
        backups << { "compacted_at" => Time.current.iso8601, "message_count" => transcript.size, "transcript" => transcript }
        metadata["pre_compact_transcripts"] = backups.last(3) # keep the three most recent backups
        session.update!(metadata: metadata)
      end
    end
  end
end
