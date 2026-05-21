# frozen_string_literal: true

module Tools
  # Stores a new memory with an explicit category. Optionally supersedes an
  # existing memory by ID, which archives the old entry and links the two.
  class MemoryStoreExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      content = input["content"].to_s.strip
      return ServiceResponse.failure(error: "No content provided") if content.empty?

      category           = validated_category(input["category"]) || "general"
      related_memory_id  = input["related_memory_id"].presence

      ActiveRecord::Base.transaction do
        entry = MemoryEntry.create!(
          agent:    agent,
          content:  content,
          category: category,
          status:   "active",
          memory_type: "semantic"
        )

        if related_memory_id.present?
          old = MemoryEntry.find_by(id: related_memory_id, agent: agent)
          old&.supersede_with!(entry)
        end

        # Queue embedding generation (same as automatic extraction path)
        MemoryEmbeddingJob.perform_later(entry.id)

        ServiceResponse.success(data: {
          output: "Memory stored (ID: #{entry.id}, category: #{category})." \
                  "#{related_memory_id.present? ? " Superseded memory ##{related_memory_id}." : ""}",
          exit_code: 0
        })
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Failed to store memory: #{e.message}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory store failed: #{e.message}")
    end

    private

    def validated_category(value)
      return nil if value.blank?
      return value if MemoryEntry::CATEGORIES.include?(value.to_s)

      nil
    end
  end
end
