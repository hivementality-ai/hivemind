# frozen_string_literal: true

module Tools
  class CreateSkillExecutor < BaseExecutor
    def call
      result = Agents::SkillCreator.call(
        agent: agent,
        name: input["name"].to_s.strip,
        summary: input["summary"].to_s.strip,
        content: input["content"].to_s.strip,
        category: input["category"],
        share_with_team: input["share_with_team"] == true
      )

      if result.success?
        ServiceResponse.success(data: { output: result.data[:output], exit_code: 0 })
      else
        ServiceResponse.failure(error: result.error)
      end
    end
  end
end
