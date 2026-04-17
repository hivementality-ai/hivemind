# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::VariableResolver do
  # Build a SwarmDocument from a JSON hash via the full parser pipeline.
  def parse_doc(hash)
    result = Swarms::SwarmParser.call(json: JSON.generate(hash))
    expect(result).to be_success, "test fixture failed to parse: #{result.error? ? result.payload&.dig(:errors) : nil}"
    result.payload
  end

  def minimal_doc
    parse_doc(swarm_version: "1.0", name: "Test Swarm")
  end

  # ---------------------------------------------------------------------------
  # No placeholders
  # ---------------------------------------------------------------------------

  describe "when the manifest has no placeholders" do
    it "succeeds with an empty resolved map" do
      result = described_class.call(document: minimal_doc)

      expect(result).to be_success
      expect(result.payload[:resolved]).to eq({})
      expect(result.payload[:missing]).to eq([])
    end

    it "returns the manifest unchanged" do
      result = described_class.call(document: minimal_doc)

      expect(result.payload[:manifest]["name"]).to eq("Test Swarm")
    end
  end

  # ---------------------------------------------------------------------------
  # Placeholder scanning
  # ---------------------------------------------------------------------------

  describe "placeholder scanning" do
    it "detects {{VAR}} in a top-level string field" do
      doc = parse_doc(swarm_version: "1.0", name: "Swarm for {{ENV}}", variables: {
        "ENV" => { required: false, default: "production" }
      })
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:manifest]["name"]).to eq("Swarm for production")
    end

    it "detects {{VAR}} in nested agent fields" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        agents: [{ name: "Bot", role: "Runs against {{ENV}}" }],
        variables: { "ENV" => { required: false, default: "staging" } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      agent_role = result.payload[:manifest]["agents"].first["role"]
      expect(agent_role).to eq("Runs against staging")
    end

    it "detects {{VAR}} in array elements (tags)" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        tags: ["env-{{ENV}}", "static"],
        variables: { "ENV" => { required: false, default: "prod" } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:manifest]["tags"]).to eq(["env-prod", "static"])
    end

    it "detects multiple distinct placeholders in the same document" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "{{TEAM_NAME}} Swarm",
        description: "Running in {{ENV}}",
        variables: {
          "TEAM_NAME" => { required: false, default: "Alpha" },
          "ENV"       => { required: false, default: "prod" }
        }
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:manifest]["name"]).to eq("Alpha Swarm")
      expect(result.payload[:manifest]["description"]).to eq("Running in prod")
    end

    it "substitutes the same placeholder multiple times across the document" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "{{ENV}} Swarm",
        description: "Environment: {{ENV}}",
        variables: { "ENV" => { required: false, default: "prod" } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:manifest]["name"]).to eq("prod Swarm")
      expect(result.payload[:manifest]["description"]).to eq("Environment: prod")
    end

    it "leaves non-matching lowercase patterns untouched" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm with {{lowercase}} placeholder",
        variables: {}
      )
      # {{lowercase}} doesn't match [A-Z][A-Z0-9_]* — it's not a valid placeholder
      result = described_class.call(document: doc)

      expect(result).to be_success
      expect(result.payload[:manifest]["name"]).to eq("Swarm with {{lowercase}} placeholder")
    end
  end

  # ---------------------------------------------------------------------------
  # Value resolution priority
  # ---------------------------------------------------------------------------

  describe "resolution priority" do
    let(:doc) do
      parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{API_URL}}",
        variables: { "API_URL" => { required: false, default: "http://default.example.com" } }
      )
    end

    it "uses caller overrides over defaults" do
      result = described_class.call(document: doc, overrides: { "API_URL" => "http://override.example.com" })

      expect(result).to be_success
      expect(result.payload[:manifest]["description"]).to eq("http://override.example.com")
      expect(result.payload[:resolved]["API_URL"]).to eq("http://override.example.com")
    end

    it "uses variable defaults when no override is provided" do
      result = described_class.call(document: doc, overrides: {})

      expect(result).to be_success
      expect(result.payload[:manifest]["description"]).to eq("http://default.example.com")
      expect(result.payload[:resolved]["API_URL"]).to eq("http://default.example.com")
    end

    it "accepts string-keyed overrides" do
      result = described_class.call(document: doc, overrides: { "API_URL" => "http://string.example.com" })

      expect(result).to be_success
      expect(result.payload[:resolved]["API_URL"]).to eq("http://string.example.com")
    end

    it "accepts symbol-keyed overrides (normalised to strings)" do
      result = described_class.call(document: doc, overrides: { API_URL: "http://sym.example.com" })

      expect(result).to be_success
      expect(result.payload[:resolved]["API_URL"]).to eq("http://sym.example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # Missing required variables
  # ---------------------------------------------------------------------------

  describe "missing required variables" do
    it "returns error when a required variable has no value" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{SECRET_TOKEN}}",
        variables: { "SECRET_TOKEN" => { required: true } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.message).to include("SECRET_TOKEN")
      expect(result.payload[:missing]).to eq(["SECRET_TOKEN"])
    end

    it "reports all missing required variables, not just the first" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{VAR_A}} and {{VAR_B}}",
        variables: {
          "VAR_A" => { required: true },
          "VAR_B" => { required: true }
        }
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.payload[:missing]).to contain_exactly("VAR_A", "VAR_B")
    end

    it "succeeds when a required variable is satisfied by override" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{SECRET_TOKEN}}",
        variables: { "SECRET_TOKEN" => { required: true } }
      )
      result = described_class.call(document: doc, overrides: { "SECRET_TOKEN" => "abc123" })

      expect(result).to be_success
      expect(result.payload[:manifest]["description"]).to eq("abc123")
    end

    it "flags a placeholder with no variable definition as missing" do
      # {{UNDEFINED}} appears in content but has no variables{} entry at all
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm {{UNDEFINED}}",
        variables: {}
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.payload[:missing]).to include("UNDEFINED")
    end

    it "flags a declared required variable with no placeholder as missing" do
      # VAR_ONLY_IN_VARS is required but never used as a placeholder
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        variables: { "VAR_ONLY_IN_VARS" => { required: true } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.payload[:missing]).to include("VAR_ONLY_IN_VARS")
    end

    it "includes partially-resolved map in error payload" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{PRESENT}} and {{ABSENT}}",
        variables: {
          "PRESENT" => { required: false, default: "here" },
          "ABSENT"  => { required: true }
        }
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.payload[:resolved]).to include("PRESENT" => "here")
      expect(result.payload[:missing]).to eq(["ABSENT"])
    end
  end

  # ---------------------------------------------------------------------------
  # Optional variables (required: false, no default)
  # ---------------------------------------------------------------------------

  describe "optional variables with no value" do
    it "does not block success for optional unresolved placeholders" do
      # Optional placeholder with no default and no override — left as literal {{VAR}}
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm {{OPTIONAL}}",
        variables: { "OPTIONAL" => { required: false } }
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      # Unresolved optional placeholders are left as-is
      expect(result.payload[:manifest]["name"]).to eq("Swarm {{OPTIONAL}}")
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    it "handles nil overrides gracefully" do
      result = described_class.call(document: minimal_doc, overrides: nil)

      expect(result).to be_success
    end

    it "returns missing as a sorted array" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        description: "{{ZEBRA}} {{ALPHA}} {{MANGO}}",
        variables: {}
      )
      result = described_class.call(document: doc)

      expect(result).to be_error
      expect(result.payload[:missing]).to eq(%w[ALPHA MANGO ZEBRA])
    end

    it "returns vault: strings without substitution (vault refs are a separate concern)" do
      doc = parse_doc(
        swarm_version: "1.0",
        name: "Swarm",
        agents: [{ name: "Agent", role: "Worker",
                   model: "vault:providers/key" }],
        variables: {}
      )
      result = described_class.call(document: doc)

      expect(result).to be_success
      agent = result.payload[:manifest]["agents"].first
      expect(agent["model"]).to eq("vault:providers/key")
    end
  end
end
