# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Teams::BuildSoul do
  describe '.call' do
    let(:team) { create(:team, name: "Development Team", description: "A team focused on building and maintaining web applications") }

    describe 'with team members' do
      let!(:agent1) do
        create(:agent, 
               team: team, 
               name: "Alice", 
               role: "Frontend Developer",
               system_prompt: "You are a frontend developer specializing in React and TypeScript. You focus on creating intuitive user interfaces and ensuring good user experience.")
      end
      
      let!(:agent2) do
        create(:agent, 
               team: team, 
               name: "Bob", 
               role: "Backend Developer",
               system_prompt: "You are a backend developer with expertise in Ruby on Rails and database design. You handle server-side logic and API development.")
      end
      
      let!(:agent3) do
        create(:agent, 
               team: team, 
               name: "Charlie", 
               role: "DevOps Engineer",
               system_prompt: nil) # No system prompt
      end

      it 'builds and saves team soul with all members' do
        result = described_class.call(team: team)

        expect(result).to be_a(String)
        expect(result).to include("# Team: Development Team")
        expect(result).to include("A team focused on building and maintaining web applications")
        expect(result).to include("## Team Members")
        expect(result).to include("### Alice — Frontend Developer")
        expect(result).to include("### Bob — Backend Developer")
        expect(result).to include("### Charlie — DevOps Engineer")
      end

      it 'includes agent system prompt summaries' do
        result = described_class.call(team: team)

        expect(result).to include("You are a frontend developer specializing in React")
        expect(result).to include("You are a backend developer with expertise in Ruby on Rails")
      end

      it 'truncates long system prompts' do
        very_long_prompt = "This is a very long system prompt that goes on and on. " * 20
        agent1.update!(system_prompt: very_long_prompt)

        result = described_class.call(team: team)

        expect(result).to include("…") # Truncation indicator
        expect(result.length).to be < very_long_prompt.length
      end

      it 'handles agents without system prompts' do
        result = described_class.call(team: team)

        # Charlie should be listed even without a system prompt
        expect(result).to include("### Charlie — DevOps Engineer")
        # But no content should follow
        charlie_section = result.split("### Charlie — DevOps Engineer")[1]
        next_section = charlie_section.split("###")[0] if charlie_section
        expect(next_section).to be_blank if next_section
      end

      it 'orders agents by name' do
        result = described_class.call(team: team)

        alice_pos = result.index("### Alice")
        bob_pos = result.index("### Bob")
        charlie_pos = result.index("### Charlie")

        expect(alice_pos).to be < bob_pos
        expect(bob_pos).to be < charlie_pos
      end

      it 'updates the team record with generated soul' do
        described_class.call(team: team)

        team.reload
        expect(team.soul).to be_present
        expect(team.soul).to include("# Team: Development Team")
        expect(team.soul).to include("## Team Members")
      end

      it 'returns the generated soul content' do
        result = described_class.call(team: team)

        team.reload
        expect(result).to eq(team.soul)
      end
    end

    describe 'with empty team' do
      let(:empty_team) { create(:team, name: "Empty Team", description: "A team with no members yet") }

      it 'handles teams with no agents' do
        result = described_class.call(team: empty_team)

        expect(result).to include("# Team: Empty Team")
        expect(result).to include("A team with no members yet")
        expect(result).to include("## Team Members")
        expect(result).to include("_No team members yet._")
      end

      it 'still updates the team record' do
        described_class.call(team: empty_team)

        empty_team.reload
        expect(empty_team.soul).to be_present
        expect(empty_team.soul).to include("_No team members yet._")
      end
    end

    describe 'with team without description' do
      let(:team_no_desc) { create(:team, name: "Minimal Team", description: nil) }
      let!(:agent) { create(:agent, team: team_no_desc, name: "Solo", role: "Developer") }

      it 'handles teams without descriptions' do
        result = described_class.call(team: team_no_desc)

        expect(result).to include("# Team: Minimal Team")
        expect(result).not_to include("A team focused on") # No description
        expect(result).to include("## Team Members")
        expect(result).to include("### Solo — Developer")
      end

      it 'handles empty string descriptions' do
        team_no_desc.update!(description: "")

        result = described_class.call(team: team_no_desc)

        expect(result).to include("# Team: Minimal Team")
        expect(result).to include("## Team Members")
        # Should not have extra blank lines from empty description
        expect(result).not_to match(/\n\n\n+/)
      end
    end

    describe 'formatting and structure' do
      let!(:agent) { create(:agent, team: team, name: "Test", role: "Tester", system_prompt: "Short prompt") }

      it 'produces well-formatted markdown' do
        result = described_class.call(team: team)

        lines = result.split("\n")
        
        # Should start with team name
        expect(lines.first).to eq("# Team: Development Team")
        
        # Should have proper section headers
        expect(lines).to include("## Team Members")
        expect(lines).to include("### Test — Tester")
        
        # Should end without trailing whitespace
        expect(result).not_to end_with("\n")
        expect(result).not_to end_with(" ")
      end

      it 'handles special characters in names and roles' do
        special_agent = create(:agent, 
                              team: team, 
                              name: "Agent-007", 
                              role: "Security & Compliance",
                              system_prompt: "You handle security & compliance issues.")

        result = described_class.call(team: team)

        expect(result).to include("### Agent-007 — Security & Compliance")
        expect(result).to include("You handle security & compliance issues.")
      end

      it 'preserves markdown formatting in system prompts' do
        markdown_agent = create(:agent,
                               team: team,
                               name: "Docs",
                               role: "Documentation",
                               system_prompt: "You write **excellent** documentation with `code examples` and *emphasis*.")

        result = described_class.call(team: team)

        expect(result).to include("You write **excellent** documentation with `code examples` and *emphasis*.")
      end
    end

    describe 'edge cases and error handling' do
      it 'handles team names with special characters' do
        special_team = create(:team, name: "Team-Ω & Co.", description: "Special chars everywhere!")
        agent = create(:agent, team: special_team, name: "Agent", role: "Worker")

        result = described_class.call(team: special_team)

        expect(result).to include("# Team: Team-Ω & Co.")
        expect(result).to include("Special chars everywhere!")
      end

      it 'handles very long team names' do
        long_name = "A" * 200
        long_team = create(:team, name: long_name, description: "Long name team")
        agent = create(:agent, team: long_team, name: "Agent", role: "Worker")

        result = described_class.call(team: long_team)

        expect(result).to include("# Team: #{long_name}")
        expect(result).to include("### Agent — Worker")
      end

      it 'handles agents with very long names or roles' do
        long_agent = create(:agent,
                           team: team,
                           name: "VeryLongAgentNameThatGoesOnAndOn",
                           role: "Senior Principal Staff Engineering Manager Lead",
                           system_prompt: "Standard prompt")

        result = described_class.call(team: team)

        expect(result).to include("### VeryLongAgentNameThatGoesOnAndOn — Senior Principal Staff Engineering Manager Lead")
      end

      it 'handles database update failures gracefully' do
        allow(team).to receive(:update!).and_raise(ActiveRecord::RecordInvalid, "Validation failed")

        expect {
          described_class.call(team: team)
        }.to raise_error(ActiveRecord::RecordInvalid, "Validation failed")
      end

      it 'handles teams with many agents efficiently' do
        # Create many agents to test performance/structure
        50.times do |i|
          create(:agent,
                 team: team,
                 name: "Agent#{i.to_s.rjust(2, '0')}",
                 role: "Role #{i}",
                 system_prompt: "System prompt for agent #{i}")
        end

        result = described_class.call(team: team)

        expect(result).to include("# Team: Development Team")
        expect(result).to include("## Team Members")
        expect(result.scan(/### Agent\d+/).count).to eq(50)
        
        # Should still be ordered by name
        expect(result.index("### Agent00")).to be < result.index("### Agent01")
        expect(result.index("### Agent01")).to be < result.index("### Agent02")
      end
    end

    describe 'system prompt truncation' do
      it 'truncates at exactly 300 characters with ellipsis' do
        long_prompt = "A" * 350 # Longer than 300 chars
        agent = create(:agent, team: team, name: "Long", role: "Talker", system_prompt: long_prompt)

        result = described_class.call(team: team)

        # Find the truncated content
        long_section = result.split("### Long — Talker")[1].split("###")[0] if result.include?("### Long — Talker")
        truncated_content = long_section.strip if long_section

        expect(truncated_content).to end_with("…")
        expect(truncated_content.length).to eq(300) # Including the ellipsis
      end

      it 'does not truncate short system prompts' do
        short_prompt = "Short and sweet."
        agent = create(:agent, team: team, name: "Brief", role: "Concise", system_prompt: short_prompt)

        result = described_class.call(team: team)

        expect(result).to include(short_prompt)
        expect(result).not_to include("…")
      end

      it 'handles exactly 300 character prompts' do
        exact_prompt = "A" * 300
        agent = create(:agent, team: team, name: "Exact", role: "Precise", system_prompt: exact_prompt)

        result = described_class.call(team: team)

        expect(result).to include(exact_prompt)
        expect(result).not_to include("…") # Should not truncate exactly 300 chars
      end
    end

    describe 'whitespace and formatting consistency' do
      it 'produces consistent spacing between sections' do
        agent = create(:agent, team: team, name: "Test", role: "Tester")

        result = described_class.call(team: team)
        lines = result.split("\n")

        # Check that sections are properly spaced
        team_name_idx = lines.index("# Team: Development Team")
        description_idx = lines.index("A team focused on building and maintaining web applications")
        members_idx = lines.index("## Team Members")

        expect(lines[team_name_idx + 1]).to eq("") # Blank line after team name
        expect(lines[description_idx + 1]).to eq("") # Blank line after description
        expect(lines[members_idx + 1]).to eq("") # Blank line after "Team Members" header
      end

      it 'strips trailing whitespace from final result' do
        agent = create(:agent, team: team, name: "Test", role: "Tester")

        result = described_class.call(team: team)

        expect(result).not_to end_with(" ")
        expect(result).not_to end_with("\n")
        expect(result).not_to end_with("\t")
      end
    end
  end
end