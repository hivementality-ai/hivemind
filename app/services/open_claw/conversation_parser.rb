# frozen_string_literal: true

module OpenClaw
  class ConversationParser
    def self.call(workspace_path:, agent:)
      new(workspace_path:, agent:).call
    end

    def initialize(workspace_path:, agent:)
      @workspace_path = workspace_path
      @agent = agent
    end

    def call
      conversations_dir = File.join(@workspace_path, "conversations")
      return ServiceResponse.success(data: { count: 0, files: [] }) unless File.directory?(conversations_dir)

      files = Dir.glob(File.join(conversations_dir, "*.json")).sort
      return ServiceResponse.success(data: { count: 0, files: [] }) if files.empty?

      count = 0
      imported_files = []

      files.each do |filepath|
        filename = File.basename(filepath)
        raw = JSON.parse(File.read(filepath))
        messages = normalize_messages(raw)
        next if messages.empty?

        # Avoid duplicates using metadata fingerprint
        source_key = "openclaw:#{filename}"
        if Session.where(agent: @agent).where("metadata @> ?", { "openclaw_source" => source_key }.to_json).exists?
          next
        end

        transcript = messages.map do |msg|
          {
            "role" => msg["role"] || "user",
            "content" => sanitize_utf8(msg["content"].to_s),
            "timestamp" => msg["timestamp"] || Time.current.iso8601
          }
        end

        Session.create!(
          agent: @agent,
          session_key: "openclaw_#{SecureRandom.uuid}",
          title: "Imported: #{filename.delete_suffix('.json')}",
          status: :archived,
          transcript: transcript,
          metadata: { "openclaw_source" => source_key, "imported_at" => Time.current.iso8601 },
          last_activity_at: Time.current
        )

        count += 1
        imported_files << filename
      end

      ServiceResponse.success(data: { count: count, files: imported_files })
    rescue StandardError => e
      ServiceResponse.failure(error: "Conversation import failed: #{e.message}")
    end

    private

    def normalize_messages(raw)
      if raw.is_a?(Array)
        raw
      elsif raw.is_a?(Hash) && raw["messages"].is_a?(Array)
        raw["messages"]
      else
        []
      end
    end

    def sanitize_utf8(str)
      str.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
         .gsub(/\xC2\xA0/, " ")
         .scrub(" ")
    end
  end
end
