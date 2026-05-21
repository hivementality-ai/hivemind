# frozen_string_literal: true

module Tools
  # Update an existing memory: change content, recategorize, or change status.
  # Re-vectorizes if content changes.
  class MemoryUpdateExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "No agent context") unless agent

      memory_id = input["memory_id"].presence
      return ServiceResponse.failure(error: "memory_id is required") if memory_id.blank?

      entry = MemoryEntry.find_by(id: memory_id, agent: agent)
      return ServiceResponse.failure(error: "Memory ##{memory_id} not found") unless entry

      new_content  = input["content"].presence
      new_category = input["category"].presence
      new_status   = input["status"].presence

      if new_category.present? && !MemoryEntry::CATEGORIES.include?(new_category)
        return ServiceResponse.failure(
          error: "Invalid category '#{new_category}'. Valid values: #{MemoryEntry::CATEGORIES.join(', ')}"
        )
      end

      if new_status.present? && !MemoryEntry::STATUSES.include?(new_status)
        return ServiceResponse.failure(
          error: "Invalid status '#{new_status}'. Valid values: #{MemoryEntry::STATUSES.join(', ')}"
        )
      end

      if new_content.blank? && new_category.blank? && new_status.blank?
        return ServiceResponse.failure(error: "Provide at least one of: content, category, status")
      end

      attrs = {}
      attrs[:category] = new_category if new_category.present?
      attrs[:status]   = new_status if new_status.present?

      content_changed = new_content.present? && new_content != entry.content
      if content_changed
        attrs[:content] = new_content
        # Re-vectorize synchronously so search reflects new content immediately
        new_embedding = Memory::Embedding.generate(new_content)
        attrs[:embedding] = new_embedding if new_embedding
      end

      entry.update!(attrs)

      ServiceResponse.success(data: {
        output: format_success(entry, content_changed),
        exit_code: 0
      })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Update failed: #{e.message}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory update failed: #{e.message}")
    end

    private

    def format_success(entry, content_changed)
      parts = ["Memory ##{entry.id} updated."]
      parts << "Content updated and re-vectorized." if content_changed
      parts << "Category: #{entry.category}."
      parts << "Status: #{entry.status}."
      parts.join(" ")
    end
  end
end
