# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::Orchestrate do
  describe '.call' do
    let(:team) { create(:team) }
    let(:orchestrator_agent) { create(:agent, team: team, role: "orchestrator") }
    let(:coder_agent) { create(:agent, team: team, role: "coder") }
    let(:researcher_agent) { create(:agent, team: team, role: "researcher") }
    let(:writer_agent) { create(:agent, team: team, role: "writer") }

    before do
      allow(SecureRandom).to receive(:uuid).and_return("orch-123-uuid")
      # Mock Agents::Delegate service
      allow(Agents::Delegate).to receive(:call).and_return(
        ServiceResponse.success(data: { message: double(id: 1), task: "delegated task" })
      )
    end

    describe 'successful orchestration' do
      context 'with coding task' do
        let(:task) { "Implement a user authentication system with proper tests" }

        it 'decomposes and delegates appropriate subtasks' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          
          data = result.data
          expect(data[:orchestration_id]).to eq("orch-123-uuid")
          expect(data[:task]).to eq(task)
          expect(data[:delegations]).to be_an(Array)
          expect(data[:plan]).to be_an(Array)
        end

        it 'delegates to coder for implementation' do
          described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(Agents::Delegate).to have_received(:call).with(
            from_agent: orchestrator_agent,
            to_agent: coder_agent,
            task: "Implement code for: #{task}",
            context: {
              orchestration_id: "orch-123-uuid",
              parent_task: task
            }
          )
        end

        it 'includes coding subtask in plan' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          plan = result.data[:plan]
          coding_subtask = plan.find { |st| st[:role] == "coder" }
          
          expect(coding_subtask).to be_present
          expect(coding_subtask[:description]).to eq("Implement code for: #{task}")
        end
      end

      context 'with research task' do
        let(:task) { "Research best practices for database optimization" }

        it 'delegates to researcher' do
          described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(Agents::Delegate).to have_received(:call).with(
            from_agent: orchestrator_agent,
            to_agent: researcher_agent,
            task: "Research requirements for: #{task}",
            context: {
              orchestration_id: "orch-123-uuid",
              parent_task: task
            }
          )
        end
      end

      context 'with documentation task' do
        let(:task) { "Write comprehensive documentation for the API" }

        it 'delegates to writer' do
          described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(Agents::Delegate).to have_received(:call).with(
            from_agent: orchestrator_agent,
            to_agent: writer_agent,
            task: "Document: #{task}",
            context: {
              orchestration_id: "orch-123-uuid",
              parent_task: task
            }
          )
        end
      end

      context 'with multi-role task' do
        let(:task) { "Build and document a new feature with proper research" }

        it 'delegates to multiple agents' do
          described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          # Should delegate to all three roles
          expect(Agents::Delegate).to have_received(:call).exactly(3).times
        end

        it 'returns multiple delegations' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(result.data[:delegations].length).to eq(3)
          expect(result.data[:plan].length).to eq(3)
        end
      end
    end

    describe 'validation failures' do
      context 'when agent is not on team' do
        let(:other_team) { create(:team) }
        let(:outside_agent) { create(:agent, team: other_team) }

        it 'returns failure' do
          result = described_class.call(
            agent: outside_agent,
            task: "Some task",
            team: team
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Agent must be on the specified team")
        end

        it 'does not make any delegations' do
          described_class.call(
            agent: outside_agent,
            task: "Some task",
            team: team
          )

          expect(Agents::Delegate).not_to have_received(:call)
        end
      end
    end

    describe 'when no suitable agents found' do
      context 'with task requiring unavailable roles' do
        let(:task) { "Implement a complex coding solution" }
        
        before do
          # Remove specialized agents, leaving only orchestrator
          [coder_agent, researcher_agent, writer_agent].each(&:destroy)
        end

        it 'returns failure when no agents can handle subtasks' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: task,
            team: team
          )

          expect(result.success?).to be false
          expect(result.error).to eq("No suitable agents found for task delegation")
        end
      end

      context 'when delegation fails' do
        before do
          allow(Agents::Delegate).to receive(:call).and_return(
            ServiceResponse.failure(error: "Delegation failed")
          )
        end

        it 'returns failure when all delegations fail' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: "Build something awesome",
            team: team
          )

          expect(result.success?).to be false
          expect(result.error).to eq("No suitable agents found for task delegation")
        end
      end
    end

    describe 'task role matching' do
      it 'identifies coding tasks correctly' do
        coding_tasks = [
          "code a new feature",
          "implement the API",
          "build the component", 
          "develop the algorithm",
          "fix the bug"
        ]

        coding_tasks.each do |task|
          service = described_class.new(agent: orchestrator_agent, task: task, team: team)
          expect(service.send(:role_needed?, "coder")).to be true
        end
      end

      it 'identifies research tasks correctly' do
        research_tasks = [
          "research the requirements",
          "find the best approach",
          "investigate the issue",
          "analyze the data"
        ]

        research_tasks.each do |task|
          service = described_class.new(agent: orchestrator_agent, task: task, team: team)
          expect(service.send(:role_needed?, "researcher")).to be true
        end
      end

      it 'identifies writing tasks correctly' do
        writing_tasks = [
          "document the process",
          "write the guide",
          "explain the concept",
          "describe the workflow"
        ]

        writing_tasks.each do |task|
          service = described_class.new(agent: orchestrator_agent, task: task, team: team)
          expect(service.send(:role_needed?, "writer")).to be true
        end
      end

      it 'excludes irrelevant roles' do
        task = "code a new feature"
        service = described_class.new(agent: orchestrator_agent, task: task, team: team)
        
        expect(service.send(:role_needed?, "researcher")).to be false
        expect(service.send(:role_needed?, "writer")).to be false
      end
    end

    describe 'agent selection' do
      it 'excludes the orchestrating agent from delegation' do
        # Make orchestrator also a coder
        orchestrator_agent.update(role: "coder")
        
        result = described_class.call(
          agent: orchestrator_agent,
          task: "Implement a feature",
          team: team
        )

        # Should delegate to the other coder, not itself
        expect(Agents::Delegate).to have_received(:call).with(
          from_agent: orchestrator_agent,
          to_agent: coder_agent, # Not orchestrator_agent
          task: anything,
          context: anything
        )
      end
    end

    describe 'partial success scenarios' do
      context 'when some delegations succeed and others fail' do
        before do
          # Mock first delegation to succeed, second to fail
          call_count = 0
          allow(Agents::Delegate).to receive(:call) do
            call_count += 1
            if call_count == 1
              ServiceResponse.success(data: { message: double(id: 1), task: "success" })
            else
              ServiceResponse.failure(error: "Failed")
            end
          end
        end

        it 'returns success with only successful delegations' do
          result = described_class.call(
            agent: orchestrator_agent,
            task: "Build and research something",
            team: team
          )

          expect(result.success?).to be true
          expect(result.data[:delegations].length).to eq(1)
        end
      end
    end

    describe 'exception handling' do
      before do
        allow(Agents::Delegate).to receive(:call).and_raise(StandardError, "Network error")
      end

      it 'returns failure with error message' do
        result = described_class.call(
          agent: orchestrator_agent,
          task: "Some task",
          team: team
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Orchestration failed: Network error")
      end
    end
  end
end