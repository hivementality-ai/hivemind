# frozen_string_literal: true

module Tools
  # Updates an existing memory in-place: content, category, and/or status.
  # Re-queues embedding generation if content changes.
  class MemoryUpdateExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "Agent context required") unless agent

      memory_id = input["memory_id"].presence
      return ServiceResponse.failure(error: "memory_id is required") if memory_id.blank?

      entry = MemoryEntry.find_by(id: memory_id, agent: agent)
      return ServiceResponse.failure(error: "Memory ##{memory_id} not found") unless entry

      updates      = {}
      content_changed = false

      if input.key?("content")
        new_content = input["content"].to_s.strip
        if new_content.empty?
          return ServiceResponse.failure(error: "content cannot be blank")
        end
        unless new_content == entry.content
          updates[:content]    = new_content
          updates[:embedding]  = nil  # clear so MemoryEmbeddingJob re-generates
          content_changed = true
        end
      end

      if input.key?("category")
        cat = validated_category(input["category"])
        return ServiceResponse.failure(error: "Invalid category: #{input['category']}") if cat.nil?
        updates[:category] = cat
      end

      if input.key?("status")
        st = validated_status(input["status"])
        return ServiceResponse.failure(error: "Invalid status: #{input['status']}") if st.nil?
        updates[:status] = st
      end

      if updates.empty?
        return ServiceResponse.success(data: {
          output: "No changes to apply to memory ##{memory_id}.",
          exit_code: 0
        })
      end

      entry.update!(updates)
      MemoryEmbeddingJob.perform_later(entry.id) if content_changed

      ServiceResponse.success(data: {
        output: "Memory ##{memory_id} updated (#{updates.except(:embedding).keys.join(', ')}).",
        exit_code: 0
      })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Failed to update memory: #{e.message}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory update failed: #{e.message}")
    end

    private

    def validated_category(value)
      return nil if value.blank?
      return value if MemoryEntry::CATEGORIES.include?(value.to_s)

      nil
    end

    def validated_status(value)
      return nil if value.blank?
      return value if MemoryEntry::STATUSES.include?(value.to_s)

      nil
    end
  end
end
