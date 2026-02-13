# frozen_string_literal: true

module HashtagActions
  module Actions
    class Search < Base
      def execute
        return { response: "Search for what? Use: #search <query>", status: "no_payload" } if payload.blank?

        memories = MemoryEntry.where(agent: agent)
                              .where("content ILIKE ?", "%#{MemoryEntry.sanitize_sql_like(payload)}%")
                              .order(created_at: :desc)
                              .limit(10)

        if memories.empty?
          { response: "No memories found for \"#{payload.truncate(60)}\".", status: "empty" }
        else
          lines = memories.map.with_index(1) do |m, i|
            "#{i}. #{m.content.truncate(120)} (#{m.created_at.strftime('%b %d')})"
          end
          { response: "Memories matching \"#{payload.truncate(40)}\":\n#{lines.join("\n")}", status: "found" }
        end
      end
    end
  end
end
