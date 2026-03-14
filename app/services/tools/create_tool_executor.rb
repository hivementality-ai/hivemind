# frozen_string_literal: true

module Tools
  class CreateToolExecutor < BaseExecutor
    def call
      parameters = input["parameters"]
      parameters = JSON.parse(parameters) if parameters.is_a?(String)

      result = Agents::ToolCreator.call(
        agent: agent,
        name: input["name"].to_s.strip,
        description: input["description"].to_s.strip,
        script_template: input["script_template"].to_s,
        parameters: parameters || {},
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
