# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::AgentSerializer do
  describe ".call" do
    context "required fields" do
      it "includes name" do
        agent = create(:agent, name: "Mando", role: "Engineer")
        expect(described_class.call(agent: agent)["name"]).to eq("Mando")
      end

      it "includes role" do
        agent = create(:agent, name: "Mando", role: "Software Engineer")
        expect(described_class.call(agent: agent)["role"]).to eq("Software Engineer")
      end
    end

    context "system_prompt / soul" do
      it "maps system_prompt to soul" do
        agent = create(:agent, name: "Mando", role: "Coder", system_prompt: "You write clean code.")
        result = described_class.call(agent: agent)
        expect(result["soul"]).to eq("You write clean code.")
      end

      it "omits soul when system_prompt is blank" do
        agent = create(:agent, name: "Mando", role: "Coder", system_prompt: nil)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("soul")
      end
    end

    context "model" do
      it "includes llm_model as model" do
        agent = create(:agent, name: "Mando", role: "Coder", llm_model: "claude-opus-4-5")
        result = described_class.call(agent: agent)
        expect(result["model"]).to eq("claude-opus-4-5")
      end

      it "omits model when llm_model is blank" do
        agent = create(:agent, name: "Mando", role: "Coder")
        agent.update_column(:llm_model, nil)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("model")
      end
    end

    context "model_config" do
      it "includes model_config when present and non-empty" do
        cfg   = { "temperature" => 0.7, "top_p" => 0.9 }
        agent = create(:agent, name: "Mando", role: "Coder", model_config: cfg)
        expect(described_class.call(agent: agent)["model_config"]).to eq(cfg)
      end

      it "omits model_config when nil" do
        agent = create(:agent, name: "Mando", role: "Coder", model_config: nil)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("model_config")
      end

      it "omits model_config when empty hash" do
        agent = create(:agent, name: "Mando", role: "Coder", model_config: {})
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("model_config")
      end
    end

    context "thinking config" do
      it "includes thinking_enabled true and budget when agent has thinking on" do
        agent = create(:agent, name: "Mando", role: "Coder",
          thinking_enabled: true, thinking_budget_tokens: 5000)
        result = described_class.call(agent: agent)
        expect(result["thinking_enabled"]).to be true
        expect(result["thinking_budget_tokens"]).to eq(5000)
      end

      it "omits thinking_enabled when false" do
        agent = create(:agent, name: "Mando", role: "Coder", thinking_enabled: false)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("thinking_enabled")
      end

      it "omits thinking_budget_tokens when thinking is disabled" do
        agent = create(:agent, name: "Mando", role: "Coder",
          thinking_enabled: false, thinking_budget_tokens: 1000)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("thinking_budget_tokens")
      end

      it "omits thinking_visibility when set to the default (hidden)" do
        agent = create(:agent, name: "Mando", role: "Coder",
          thinking_enabled: true, thinking_budget_tokens: 1000, thinking_visibility: "hidden")
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("thinking_visibility")
      end

      it "includes thinking_visibility when set to debug" do
        agent = create(:agent, name: "Mando", role: "Coder",
          thinking_enabled: true, thinking_budget_tokens: 1000, thinking_visibility: "debug")
        result = described_class.call(agent: agent)
        expect(result["thinking_visibility"]).to eq("debug")
      end
    end

    context "skills" do
      it "includes skill names as an array" do
        agent  = create(:agent, name: "Mando", role: "Coder")
        skill1 = create(:skill, name: "git-workflow")
        skill2 = create(:skill, name: "code-review")
        agent.skills << skill1 << skill2

        result = described_class.call(agent: agent)
        expect(result["skills"]).to match_array(%w[git-workflow code-review])
      end

      it "omits skills key when agent has no skills" do
        agent = create(:agent, name: "Mando", role: "Coder")
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("skills")
      end
    end

    context "tools" do
      it "includes tool names as an array" do
        agent = create(:agent, name: "Mando", role: "Coder")
        tool1 = create(:tool, name: "web-search",
          executor_type: "custom_script", script_template: "echo hi")
        tool2 = create(:tool, name: "file-read",
          executor_type: "custom_script", script_template: "cat {{path}}")
        agent.tools << tool1 << tool2

        result = described_class.call(agent: agent)
        expect(result["tools"]).to match_array(%w[web-search file-read])
      end

      it "omits tools key when agent has no tools" do
        agent = create(:agent, name: "Mando", role: "Coder")
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("tools")
      end
    end

    context "egress_policy" do
      it "includes egress_policy when mode is set" do
        agent = create(:agent, name: "Mando", role: "Coder",
          egress_policy: { "mode" => "allowlist", "rules" => [] })
        result = described_class.call(agent: agent)
        expect(result["egress_policy"]).to eq({ "mode" => "allowlist", "rules" => [] })
      end

      it "omits egress_policy when blank" do
        agent = create(:agent, name: "Mando", role: "Coder", egress_policy: {})
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("egress_policy")
      end
    end

    context "tool_loop_config" do
      it "omits tool_loop_config when it matches the default" do
        agent = create(:agent, name: "Mando", role: "Coder",
          tool_loop_config: Agent::DEFAULT_LOOP_CONFIG)
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("tool_loop_config")
      end

      it "includes tool_loop_config when it differs from the default" do
        custom_cfg = { "history_size" => 50 }
        agent = create(:agent, name: "Mando", role: "Coder", tool_loop_config: custom_cfg)
        result = described_class.call(agent: agent)
        expect(result["tool_loop_config"]).to eq(custom_cfg)
      end

      it "omits tool_loop_config when empty" do
        agent = create(:agent, name: "Mando", role: "Coder", tool_loop_config: {})
        result = described_class.call(agent: agent)
        expect(result).not_to have_key("tool_loop_config")
      end
    end

    context "schema conformance" do
      it "produces output that is valid against SwarmSchema agents section" do
        agent = create(:agent, name: "Mando", role: "Engineer",
          system_prompt:          "You are an engineer.",
          llm_model:              "claude-opus-4-5",
          thinking_enabled:       true,
          thinking_budget_tokens: 8000)
        skill = create(:skill, name: "coding-skill")
        agent.skills << skill

        result = described_class.call(agent: agent)
        raw    = { "swarm_version" => "1.0", "name" => "Test", "agents" => [ result ] }

        validation = Swarms::SwarmSchema.validate(raw)
        expect(validation).to be_valid, validation.errors.inspect
      end
    end
  end
end
