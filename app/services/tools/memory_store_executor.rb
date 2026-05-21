# frozen_string_literal: true

module Tools
  # Explicit memory creation with category support and optional supersede-linking.
  # Stores a new memory, optionally archiving an existing one that this supersedes.
  class MemoryStoreExecutor < BaseExecutor
    def call
      return ServiceResponse.failure(error: "No agent context") unless agent

      content  = input["content"].to_s.strip
      return ServiceResponse.failure(error: "content is required") if content.empty?

      category           = input["category"].presence || "general"
      related_memory_id  = input["related_memory_id"].presence

      unless MemoryEntry::CATEGORIES.include?(category)
        return ServiceResponse.failure(
          error: "Invalid category '#{category}'. Valid values: #{MemoryEntry::CATEGORIES.join(', ')}"
        )
      end

      superseded_entry = resolve_related_memory(related_memory_id)
      return superseded_entry if superseded_entry.is_a?(ServiceResponse)

      result = Memory::Store.call(
        agent: agent,
        content: content,
        category: category,
        async: false
      )

      return ServiceResponse.failure(error: result.error) unless result.success?

      new_entry = result.data[:memory_entry]

      # Archive the old memory and link it to the new one
      if superseded_entry
        superseded_entry.archive!(superseded_by: new_entry)
      end

      ServiceResponse.success(data: {
        output: format_success(new_entry, superseded_entry),
        exit_code: 0
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Memory store failed: #{e.message}")
    end

    private

    def resolve_related_memory(related_memory_id)
      return nil if related_memory_id.blank?

      entry = MemoryEntry.find_by(id: related_memory_id, agent: agent)
      return ServiceResponse.failure(error: "Memory ##{related_memory_id} not found") unless entry

      entry
    end

    def format_success(entry, superseded)
      parts = ["Memory stored (ID: #{entry.id}, category: #{entry.category})."]
      parts << "Archived memory ##{superseded.id} as superseded." if superseded
      parts.join(" ")
    end
  end
end
