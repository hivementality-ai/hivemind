# frozen_string_literal: true

module Agents
  class PlanGenerator
    def self.call(agent:, task:, session: nil)
      new(agent: agent, task: task, session: session).call
    end

    def initialize(agent:, task:, session: nil)
      @agent = agent
      @task = task
      @session = session
    end

    def call
      # Resolve provider
      resolver = Providers::Resolver.call(provider_name: @agent.model_provider, agent: @agent)
      unless resolver.success?
        return ServiceResponse.failure(error: resolver.error)
      end

      adapter = resolver.data[:adapter]

      # Build planning prompt
      system_prompt = build_planning_system_prompt
      user_prompt = build_planning_user_prompt

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]

      # Call LLM with instruction to generate structured plan
      options = { model: @agent.llm_model, max_tokens: 4096 }

      result = adapter.chat(messages: messages, options: options)
      return result unless result.success?

      # Parse the response as JSON
      content = result.data[:content].to_s
      plan = parse_plan_from_response(content)

      unless plan
        return ServiceResponse.failure(error: "Failed to parse plan from LLM response")
      end

      ServiceResponse.success(data: { plan: plan })
    rescue StandardError => e
      ServiceResponse.failure(error: "Plan generation failed: #{e.message}")
    end

    private

    def build_planning_system_prompt
      <<~PROMPT
        You are an expert planner. Your task is to generate detailed, structured work plans.

        When asked to create a plan, respond ONLY with valid JSON in this exact format (no other text):

        {
          "overview": "Brief 1-2 sentence summary of the work",
          "context": "Relevant context and constraints",
          "phases": [
            {
              "number": 1,
              "name": "Phase name",
              "objectives": ["objective 1", "objective 2"],
              "approach": "How to accomplish the objectives",
              "tools_needed": ["tool1", "tool2"],
              "expected_output": "What this phase should produce"
            }
          ],
          "success_criteria": ["criterion 1", "criterion 2"],
          "estimated_duration": "Rough estimate of time needed"
        }

        Guidelines:
        - Create 3-5 sequential phases
        - Each phase should be clearly defined with specific objectives
        - Include concrete tools/approaches that can be referenced
        - Each phase should be achievable in a reasonably sized task
        - Success criteria should be measurable
      PROMPT
    end

    def build_planning_user_prompt
      <<~PROMPT
        Create a detailed execution plan for the following task:

        #{@task}

        Remember to respond ONLY with the JSON plan structure. No explanations, no preamble.
      PROMPT
    end

    def parse_plan_from_response(content)
      # Try to extract JSON from the response
      json_match = content.match(/\{.*\}/m)
      return nil unless json_match

      begin
        plan = JSON.parse(json_match[0])
        
        # Validate structure
        required_keys = %w[overview context phases success_criteria estimated_duration]
        return nil unless required_keys.all? { |k| plan[k].present? }
        
        # Validate phases
        phases = plan["phases"]
        return nil unless phases.is_a?(Array) && phases.any?
        
        phases.each do |phase|
          return nil unless phase["number"].present? && phase["name"].present? && phase["objectives"].present?
        end

        plan
      rescue JSON::ParserError
        nil
      end
    end
  end
end
