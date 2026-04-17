# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::ToolSerializer do
  describe ".call" do
    context "with a builtin tool" do
      let(:tool) { build(:tool, name: "web_search", builtin: true) }

      it "returns only the name" do
        result = described_class.call(tool: tool)
        expect(result).to eq({ "name" => "web_search" })
      end

      it "does not include script_template" do
        result = described_class.call(tool: tool)
        expect(result).not_to have_key("script_template")
      end

      it "does not include parameters" do
        result = described_class.call(tool: tool)
        expect(result).not_to have_key("parameters")
      end
    end

    context "with a custom tool" do
      let(:tool) do
        build(:tool,
          name:             "deploy-service",
          description:      "Deploys a service to the cluster",
          executor_type:    "custom_script",
          script_template:  "#!/bin/bash\ndeploy.sh {{service}}",
          builtin:          false,
          parameters_schema: {
            "properties" => {
              "service" => { "type" => "string", "description" => "Service to deploy" },
              "env"     => { "type" => "string", "description" => "Target environment" }
            },
            "required" => [ "service" ]
          }
        )
      end

      it "includes name" do
        expect(described_class.call(tool: tool)["name"]).to eq("deploy-service")
      end

      it "includes description" do
        expect(described_class.call(tool: tool)["description"]).to eq("Deploys a service to the cluster")
      end

      it "includes script_template" do
        expect(described_class.call(tool: tool)["script_template"]).to eq("#!/bin/bash\ndeploy.sh {{service}}")
      end

      it "converts parameters_schema back to swarm parameters format" do
        params = described_class.call(tool: tool)["parameters"]

        expect(params["service"]["type"]).to eq("string")
        expect(params["service"]["description"]).to eq("Service to deploy")
        expect(params["service"]["required"]).to be true

        expect(params["env"]["required"]).to be false
      end

      it "omits script_template when blank" do
        tool_no_script = build(:tool,
          name:            "bare-tool",
          description:     "A tool",
          executor_type:   "custom_script",
          script_template: nil,
          builtin:         false
        )
        result = described_class.call(tool: tool_no_script)
        expect(result).not_to have_key("script_template")
      end

      it "omits parameters when schema is empty" do
        tool_no_params = build(:tool,
          name:              "no-params-tool",
          description:       "A tool",
          executor_type:     "custom_script",
          script_template:   "echo hi",
          builtin:           false,
          parameters_schema: {}
        )
        result = described_class.call(tool: tool_no_params)
        expect(result).not_to have_key("parameters")
      end
    end

    context "parameters serialization round-trip" do
      it "converts required fields correctly" do
        tool = build(:tool,
          name:              "round-trip",
          description:       "D",
          executor_type:     "custom_script",
          script_template:   "echo hi",
          builtin:           false,
          parameters_schema: {
            "properties" => {
              "alpha" => { "type" => "integer", "description" => "Alpha value" },
              "beta"  => { "type" => "string",  "description" => "Beta value"  }
            },
            "required" => [ "alpha" ]
          }
        )
        params = described_class.call(tool: tool)["parameters"]

        expect(params["alpha"]["required"]).to be true
        expect(params["beta"]["required"]).to be false
        expect(params["alpha"]["type"]).to eq("integer")
      end

      it "defaults type to string when missing from schema" do
        tool = build(:tool,
          name:              "type-default",
          description:       "D",
          executor_type:     "custom_script",
          script_template:   "echo hi",
          builtin:           false,
          parameters_schema: {
            "properties" => { "foo" => { "description" => "no type" } }
          }
        )
        params = described_class.call(tool: tool)["parameters"]
        expect(params["foo"]["type"]).to eq("string")
      end
    end

    it "produces output that is valid against SwarmSchema tools section" do
      tool = build(:tool,
        name:             "valid-tool",
        description:      "A valid tool",
        executor_type:    "custom_script",
        script_template:  "echo hi",
        builtin:          false,
        parameters_schema: {}
      )
      result = described_class.call(tool: tool)

      raw = { "swarm_version" => "1.0", "name" => "Test", "tools" => [ result ] }
      validation = Swarms::SwarmSchema.validate(raw)
      expect(validation).to be_valid
    end
  end
end
