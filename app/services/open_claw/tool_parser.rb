# frozen_string_literal: true

module OpenClaw
  class ToolParser
    def self.call(workspace_path:, agent:)
      new(workspace_path:, agent:).call
    end

    def initialize(workspace_path:, agent:)
      @workspace_path = workspace_path
      @agent = agent
    end

    def call
      config_path = File.join(@workspace_path, "config.json")
      return ServiceResponse.success(data: { created: [], skipped: [], details: [] }) unless File.exist?(config_path)

      config = JSON.parse(File.read(config_path))
      tools_data = config["tools"] || []
      return ServiceResponse.success(data: { created: [], skipped: [], details: [] }) if tools_data.empty?

      created = []
      skipped = []

      tools_data.each do |tool_data|
        name = tool_data["name"]
        next if name.blank?

        # Skip tools that collide with builtins
        if Tool.builtin.exists?(name: name)
          skipped << { name: name, reason: "Collides with builtin tool" }
          next
        end

        description = tool_data["description"] || "Imported from OpenClaw"
        script = tool_data["script"] || tool_data["command"] || ""

        tool = Tool.find_or_initialize_by(name: name)
        if tool.new_record?
          tool.assign_attributes(
            description: description,
            executor_type: "custom_script",
            builtin: false,
            enabled: true,
            script_template: script.presence || "echo 'No script configured'",
            config: sanitize_tool_config(tool_data.fetch("config", {})),
            parameters_schema: tool_data["parameters"] || { "properties" => {}, "required" => [] }
          )
          tool.save!
          AgentTool.find_or_create_by!(agent: @agent, tool: tool)
          created << { name: name }
        else
          # Already exists, just create the join
          AgentTool.find_or_create_by!(agent: @agent, tool: tool)
          skipped << { name: name, reason: "Tool already exists, linked to agent" }
        end
      end

      ServiceResponse.success(data: { created: created, skipped: skipped, details: tools_data.map { |t| t["name"] } })
    rescue StandardError => e
      ServiceResponse.failure(error: "Tool import failed: #{e.message}")
    end

    private

    def sanitize_tool_config(config)
      return {} unless config.is_a?(Hash)

      config.reject { |key, _| key.match?(/token|key|secret|password|credential/i) }
    end
  end
end
