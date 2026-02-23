# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::PlanGenerator do
  let(:agent) { create(:agent) }
  let(:task) { "Build a user authentication system for a web application" }
  let(:session) { create(:session, agent: agent) }

  describe "#call" do
    let(:llm_response) do
      {
        "overview" => "Implement a complete authentication system",
        "context" => "Building secure login and signup for the web app with session management",
        "phases" => [
          {
            "number" => 1,
            "name" => "Database Setup",
            "objectives" => [ "Create user table", "Add password hashing" ],
            "approach" => "Write migration and configure bcrypt",
            "tools_needed" => [ "rails migration", "bcrypt gem" ],
            "expected_output" => "User table with encrypted passwords"
          },
          {
            "number" => 2,
            "name" => "Authentication Routes",
            "objectives" => [ "Create signup endpoint", "Create login endpoint" ],
            "approach" => "Build controller actions and views",
            "tools_needed" => [ "rails controller", "form helpers" ],
            "expected_output" => "Working signup and login pages"
          },
          {
            "number" => 3,
            "name" => "Session Management",
            "objectives" => [ "Implement session storage", "Add logout functionality" ],
            "approach" => "Use Rails session middleware",
            "tools_needed" => [ "rails sessions" ],
            "expected_output" => "User sessions persisting across requests"
          }
        ],
        "success_criteria" => [
          "Users can create accounts",
          "Users can log in securely",
          "Sessions persist across page refreshes",
          "Users can log out"
        ],
        "estimated_duration" => "4-6 hours"
      }
    end

    context "when LLM successfully generates a plan" do
      before do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: llm_response.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "calls the LLM with a planning prompt" do
        adapter = double("adapter")
        expect(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: llm_response.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)

        described_class.call(agent: agent, task: task, session: session)
      end

      it "returns success with the parsed plan" do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: llm_response.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)

        result = described_class.call(agent: agent, task: task, session: session)

        expect(result.success?).to be true
        expect(result.data[:plan]).to be_a(Hash)
        expect(result.data[:plan]["overview"]).to eq(llm_response["overview"])
        expect(result.data[:plan]["phases"].length).to eq(3)
      end

      it "validates the plan structure" do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: llm_response.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)

        result = described_class.call(agent: agent, task: task, session: session)
        plan = result.data[:plan]

        expect(plan).to have_key("overview")
        expect(plan).to have_key("context")
        expect(plan).to have_key("phases")
        expect(plan).to have_key("success_criteria")
        expect(plan).to have_key("estimated_duration")

        plan["phases"].each do |phase|
          expect(phase).to have_key("number")
          expect(phase).to have_key("name")
          expect(phase).to have_key("objectives")
          expect(phase).to have_key("approach")
          expect(phase).to have_key("tools_needed")
        end
      end
    end

    context "when provider resolution fails" do
      before do
        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(false)
        allow(resolver).to receive(:error).and_return("Provider not found")
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "returns failure with the resolver error" do
        result = described_class.call(agent: agent, task: task, session: session)
        expect(result.success?).to be false
        expect(result.error).to eq("Provider not found")
      end
    end

    context "when LLM returns invalid JSON" do
      before do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: "This is not JSON" })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "returns failure with a parsing error" do
        result = described_class.call(agent: agent, task: task, session: session)
        expect(result.success?).to be false
        expect(result.error).to include("Failed to parse plan")
      end
    end

    context "when LLM returns incomplete plan structure" do
      let(:incomplete_plan) do
        {
          "overview" => "Test plan",
          # Missing context, phases, success_criteria
          "estimated_duration" => "2 hours"
        }
      end

      before do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: incomplete_plan.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "returns failure because required fields are missing" do
        result = described_class.call(agent: agent, task: task, session: session)
        expect(result.success?).to be false
        expect(result.error).to include("Failed to parse plan")
      end
    end

    context "when LLM call fails" do
      before do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_raise(StandardError, "API error")

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "returns failure with the error message" do
        result = described_class.call(agent: agent, task: task, session: session)
        expect(result.success?).to be false
        expect(result.error).to include("Plan generation failed")
      end
    end

    context "when task is empty" do
      let(:task) { "" }

      before do
        adapter = double("adapter")
        allow(adapter).to receive(:chat).and_return(
          ServiceResponse.success(data: { content: llm_response.to_json })
        )

        resolver = double("resolver")
        allow(resolver).to receive(:success?).and_return(true)
        allow(resolver).to receive(:data).and_return({ adapter: adapter })
        allow(Providers::Resolver).to receive(:call).and_return(resolver)
      end

      it "still attempts to generate a plan" do
        result = described_class.call(agent: agent, task: task, session: session)
        # Empty task should still work - it just generates a default plan
        expect(result.success?).to be true
      end
    end
  end
end
