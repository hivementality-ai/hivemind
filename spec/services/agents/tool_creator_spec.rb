# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ToolCreator, type: :service do
  let(:agent) { create(:agent) }

  let(:valid_params) do
    {
      agent: agent,
      name: "csv_converter",
      description: "Convert CSV to JSON",
      script_template: "#!/bin/bash\ncd /workspace\ncat {{input_file}} | python3 -c 'import csv,json,sys; print(json.dumps(list(csv.DictReader(sys.stdin))))'",
      parameters: {
        "input_file" => { "type" => "string", "description" => "Path to CSV file", "required" => true }
      }
    }
  end

  describe ".call" do
    it "creates a tool pending approval" do
      result = described_class.call(**valid_params)

      expect(result).to be_success
      expect(result.data[:status]).to eq("pending_approval")

      tool = Tool.find_by(name: "csv_converter")
      expect(tool).to be_present
      expect(tool.enabled).to be false
      expect(tool.executor_type).to eq("custom_script")
      expect(tool.config["created_by_agent_id"]).to eq(agent.id)
    end

    it "builds parameter schema correctly" do
      described_class.call(**valid_params)

      tool = Tool.find_by(name: "csv_converter")
      expect(tool.parameters_schema["properties"]["input_file"]["type"]).to eq("string")
      expect(tool.parameters_schema["required"]).to include("input_file")
    end

    it "creates an approval request" do
      expect {
        described_class.call(**valid_params)
      }.to change(ApprovalRequest, :count).by(1)

      approval = ApprovalRequest.last
      expect(approval.action).to eq("create_tool")
      expect(approval.params["tool_name"]).to eq("csv_converter")
    end

    it "blocks scripts with forbidden patterns" do
      result = described_class.call(**valid_params.merge(
        script_template: "rm -rf / && echo done"
      ))

      expect(result).not_to be_success
      expect(result.error).to include("blocked")
    end

    it "blocks scripts accessing credentials" do
      result = described_class.call(**valid_params.merge(
        script_template: "echo $API_KEY > /workspace/out.txt"
      ))

      expect(result).not_to be_success
      expect(result.error).to include("blocked")
    end

    it "fails when name is blank" do
      result = described_class.call(**valid_params.merge(name: ""))
      expect(result).not_to be_success
      expect(result.error).to eq("Name is required")
    end

    it "fails when tool already exists" do
      create(:tool, name: "csv_converter")

      result = described_class.call(**valid_params)
      expect(result).not_to be_success
      expect(result.error).to include("already exists")
    end

    it "fails when script exceeds max length" do
      result = described_class.call(**valid_params.merge(
        script_template: "x" * 10_001
      ))

      expect(result).not_to be_success
      expect(result.error).to include("too long")
    end

    describe "vault secrets" do
      let(:secret_params) do
        valid_params.merge(
          name: "stripe_balance",
          script_template: "#!/bin/bash\ncurl -s -H \"Authorization: Bearer $STRIPE_API_KEY\" https://api.stripe.com/v1/balance",
          secrets: { "STRIPE_API_KEY" => "vault:stripe/api_key" }
        )
      end

      before { create(:vault_entry, namespace: "stripe", key: "api_key") }

      it "allows a script to use a declared secret by vault reference" do
        result = described_class.call(**secret_params)

        expect(result).to be_success
        expect(Tool.find_by(name: "stripe_balance").config["secret_refs"]).to eq("STRIPE_API_KEY" => "vault:stripe/api_key")
      end

      it "still blocks secret-like words that were not declared" do
        result = described_class.call(**secret_params.merge(script_template: "echo $OTHER_TOKEN"))

        expect(result.error).to include("blocked")
      end

      it "rejects a raw secret passed instead of a reference" do
        result = described_class.call(**secret_params.merge(secrets: { "STRIPE_API_KEY" => "sk-live-abcdef123456" }))

        expect(result).not_to be_success
        expect(result.error).to include("vault reference")
        expect(result.error).not_to include("sk-live-abcdef123456")
        expect(Tool.find_by(name: "stripe_balance")).to be_nil
      end

      it "rejects a reference to an entry that does not exist" do
        result = described_class.call(**secret_params.merge(secrets: { "STRIPE_API_KEY" => "vault:stripe/missing" }))

        expect(result.error).to include("does not exist")
      end

      it "rejects secret names that are not environment variables" do
        result = described_class.call(**secret_params.merge(secrets: { "bad name" => "vault:stripe/api_key" }))

        expect(result.error).to include("UPPER_SNAKE_CASE")
      end
    end

    it "adds warnings for scripts referencing paths outside workspace" do
      described_class.call(**valid_params.merge(
        script_template: "#!/bin/bash\nls /home/user/data"
      ))

      tool = Tool.find_by(name: "csv_converter")
      warnings = tool.config.dig("security_scan", "warnings")
      expect(warnings).to include(a_string_matching(/outside \/workspace/))
    end
  end
end
