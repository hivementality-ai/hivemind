# frozen_string_literal: true

module HashtagActions
  module Actions
    class Forget < Base
      def execute
        return { response: "What should I forget? Use: #forget <keyword>", status: "no_payload" } if payload.blank?

        matches = MemoryEntry.where(agent: agent)
                             .where("content ILIKE ?", "%#{MemoryEntry.sanitize_sql_like(payload)}%")
                             .order(created_at: :desc)
                             .limit(5)

        if matches.empty?
          { response: "No memories found matching \"#{payload.truncate(60)}\".", status: "not_found" }
        else
          count = matches.destroy_all.length
          { response: "Forgotten #{count} memory#{count == 1 ? '' : 'ies'} matching \"#{payload.truncate(60)}\".", status: "deleted" }
        end
      end
    end
  end
end
