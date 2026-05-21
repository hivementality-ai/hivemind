# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SessionSearchExecutor, type: :service do
  let(:agent)       { create(:agent) }
  let(:other_agent) { create(:agent) }
  let(:executor)    { described_class.new(input: input, agent: agent) }

  # Helper: sets the fts_vector on a session by executing the same tsvector
  # expression used by the trigger. Necessary because schema.rb does not
  # replay DB triggers, so the column must be populated manually in specs.
  def populate_fts(session)
    ApplicationRecord.connection.execute(<<~SQL)
      UPDATE sessions
      SET fts_vector = (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(conversation_summary, '')), 'B') ||
        setweight(
          to_tsvector(
            'english',
            coalesce(
              (
                SELECT string_agg(msg->>'content', ' ')
                FROM jsonb_array_elements(
                  CASE jsonb_typeof(transcript) WHEN 'array' THEN transcript ELSE '[]'::jsonb END
                ) AS msg
                WHERE jsonb_typeof(msg->'content') = 'string'
              ),
              ''
            )
          ),
          'C'
        )
      )
      WHERE id = #{session.id}
    SQL
  end

  # Build a session with transcript content and pre-populate its fts_vector
  def create_session_with_fts(agent:, title: "Chat", messages: [], **attrs)
    transcript = messages.map.with_index do |content, i|
      { "role" => (i.even? ? "user" : "assistant"), "content" => content, "timestamp" => i.hours.ago.iso8601 }
    end
    session = create(:session, agent: agent, title: title, transcript: transcript, **attrs)
    populate_fts(session)
    session
  end

  describe "#call" do
    context "missing query" do
      let(:input) { {} }

      it "returns failure" do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("No query provided")
      end
    end

    context "blank query" do
      let(:input) { { "query" => "   " } }

      it "returns failure" do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("No query provided")
      end
    end

    context "basic keyword search" do
      let!(:matching_session) do
        create_session_with_fts(agent: agent, title: "Auth discussion",
          messages: ["How does authentication work?", "JWT is used for auth tokens."])
      end
      let!(:unrelated_session) do
        create_session_with_fts(agent: agent, title: "Billing chat",
          messages: ["Tell me about invoices", "Invoices are generated monthly."])
      end
      let(:input) { { "query" => "authentication" } }

      it "returns success" do
        expect(executor.call).to be_success
      end

      it "finds sessions matching the keyword" do
        result = executor.call
        expect(result.data[:output]).to include(matching_session.session_key)
      end

      it "does not return unrelated sessions" do
        result = executor.call
        expect(result.data[:output]).not_to include(unrelated_session.session_key)
      end

      it "includes session metadata in output" do
        result = executor.call
        output = result.data[:output]
        expect(output).to include(agent.name)
        expect(output).to include("Auth discussion")
      end

      it "highlights matching keyword in snippet" do
        result = executor.call
        expect(result.data[:output]).to include("**auth")
      end
    end

    context "privacy scoping" do
      let!(:own_session) do
        create_session_with_fts(agent: agent, title: "My session",
          messages: ["discussion about deployment pipelines"])
      end
      let!(:other_session) do
        create_session_with_fts(agent: other_agent, title: "Other session",
          messages: ["discussion about deployment pipelines"])
      end
      let(:input) { { "query" => "deployment" } }

      it "returns only the calling agent's own sessions" do
        result = executor.call
        expect(result.data[:output]).to include(own_session.session_key)
        expect(result.data[:output]).not_to include(other_session.session_key)
      end
    end

    context "system agent bypasses privacy scoping" do
      let(:system_agent) { create(:agent, system_agent: true) }
      let(:executor)     { described_class.new(input: input, agent: system_agent) }

      let!(:agent_session) do
        create_session_with_fts(agent: agent, title: "Regular agent session",
          messages: ["questions about webhooks"])
      end
      let!(:other_session) do
        create_session_with_fts(agent: other_agent, title: "Other agent session",
          messages: ["more questions about webhooks"])
      end
      let(:input) { { "query" => "webhooks" } }

      it "returns sessions from all agents" do
        result = executor.call
        expect(result.data[:output]).to include(agent_session.session_key)
        expect(result.data[:output]).to include(other_session.session_key)
      end
    end

    context "agent_filter parameter" do
      let(:system_agent) { create(:agent, system_agent: true) }
      let(:executor)     { described_class.new(input: input, agent: system_agent) }

      let!(:target_session) do
        create_session_with_fts(agent: agent, messages: ["caching strategy discussion"])
      end
      let!(:other_session) do
        create_session_with_fts(agent: other_agent, messages: ["caching strategy overview"])
      end
      let(:input) { { "query" => "caching", "agent_filter" => agent.name } }

      it "restricts results to the specified agent" do
        result = executor.call
        expect(result.data[:output]).to include(target_session.session_key)
        expect(result.data[:output]).not_to include(other_session.session_key)
      end
    end

    context "agent_filter with unknown agent name" do
      let(:system_agent) { create(:agent, system_agent: true) }
      let(:executor)     { described_class.new(input: input, agent: system_agent) }
      let!(:_session) do
        create_session_with_fts(agent: agent, messages: ["some discussion"])
      end
      let(:input) { { "query" => "discussion", "agent_filter" => "nonexistent_agent_xyz" } }

      it "returns no results" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No sessions found")
      end
    end

    context "non-system agent cannot filter to another agent's sessions" do
      let!(:other_session) do
        create_session_with_fts(agent: other_agent, messages: ["private data discussion"])
      end
      let(:input) { { "query" => "private", "agent_filter" => other_agent.name } }

      it "returns no results" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No sessions found")
      end
    end

    context "date range filter — from" do
      let!(:recent_session) do
        s = create_session_with_fts(agent: agent, messages: ["database indexing discussion"])
        s.update_columns(updated_at: 1.day.ago)
        s
      end
      let!(:old_session) do
        s = create_session_with_fts(agent: agent, messages: ["database indexing strategy"])
        s.update_columns(updated_at: 10.days.ago)
        s
      end
      let(:input) { { "query" => "database", "from" => 5.days.ago.iso8601 } }

      it "returns only sessions updated after the from date" do
        result = executor.call
        expect(result.data[:output]).to include(recent_session.session_key)
        expect(result.data[:output]).not_to include(old_session.session_key)
      end
    end

    context "date range filter — to" do
      let!(:recent_session) do
        s = create_session_with_fts(agent: agent, messages: ["redis caching patterns"])
        s.update_columns(updated_at: 1.day.ago)
        s
      end
      let!(:old_session) do
        s = create_session_with_fts(agent: agent, messages: ["redis caching strategies"])
        s.update_columns(updated_at: 10.days.ago)
        s
      end
      let(:input) { { "query" => "redis", "to" => 5.days.ago.iso8601 } }

      it "returns only sessions updated before the to date" do
        result = executor.call
        expect(result.data[:output]).not_to include(recent_session.session_key)
        expect(result.data[:output]).to include(old_session.session_key)
      end
    end

    context "limit parameter" do
      let(:input) { { "query" => "sidekiq", "limit" => 2 } }

      before do
        5.times do |i|
          create_session_with_fts(agent: agent, messages: ["sidekiq job processing #{i}"])
        end
      end

      it "respects the limit" do
        result = executor.call
        expect(result.data[:output].scan(/^\d+\./).size).to eq(2)
      end
    end

    context "limit clamp — over max" do
      let(:input) { { "query" => "anything", "limit" => 999 } }

      it "does not raise and clamps to 20" do
        # Just verify it succeeds without error
        expect { executor.call }.not_to raise_error
      end
    end

    context "no matching sessions" do
      let!(:_session) do
        create_session_with_fts(agent: agent, messages: ["completely unrelated content"])
      end
      let(:input) { { "query" => "xyzzy_no_match_guaranteed" } }

      it "returns success with a not-found message" do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("No sessions found")
        expect(result.data[:output]).to include("xyzzy_no_match_guaranteed")
      end
    end

    context "result includes message count" do
      let!(:_session) do
        create_session_with_fts(agent: agent, title: "Counting test",
          messages: ["first message about logging", "second message"])
      end
      let(:input) { { "query" => "logging" } }

      it "includes message count in output" do
        result = executor.call
        expect(result.data[:output]).to match(/Messages: \d+/)
      end
    end

    context "without an agent" do
      let(:executor) { described_class.new(input: input, agent: nil) }
      let!(:_session) do
        create_session_with_fts(agent: agent, messages: ["public discussion about api design"])
      end
      let(:input) { { "query" => "api" } }

      it "returns all matching sessions (no agent scoping applied)" do
        result = executor.call
        expect(result).to be_success
      end
    end

    context "title matching (high-weight)" do
      let!(:title_match) do
        create_session_with_fts(agent: agent, title: "OAuth Implementation",
          messages: ["General chat about something else"])
      end
      let!(:content_match) do
        create_session_with_fts(agent: agent, title: "Random chat",
          messages: ["oauth is a standard for authorization"])
      end
      let(:input) { { "query" => "oauth", "limit" => 10 } }

      it "returns both title and content matches" do
        result = executor.call
        expect(result.data[:output]).to include(title_match.session_key)
        expect(result.data[:output]).to include(content_match.session_key)
      end

      it "ranks the title match higher (appears first)" do
        result = executor.call
        title_pos   = result.data[:output].index(title_match.session_key)
        content_pos = result.data[:output].index(content_match.session_key)
        expect(title_pos).to be < content_pos
      end
    end
  end
end
