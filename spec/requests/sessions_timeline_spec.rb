# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session Timeline", type: :request do
  let(:user)    { create(:user, :owner) }
  let(:agent)   { create(:agent) }
  let(:session) { create(:session, :with_transcript, agent: agent) }

  before { sign_in user }

  describe "GET /sessions/:id/timeline" do
    context "with interleaved activity" do
      let!(:tool_exec) do
        create(:tool_execution, :completed,
               session: session,
               agent: agent,
               created_at: 30.minutes.ago)
      end

      let!(:usage) do
        create(:usage_record,
               session: session,
               agent: agent,
               input_tokens: 200,
               output_tokens: 80,
               cost_cents: 25,
               created_at: 20.minutes.ago)
      end

      it "returns HTTP 200" do
        get timeline_session_path(session)
        expect(response).to have_http_status(:ok)
      end

      it "renders message entries" do
        get timeline_session_path(session)
        expect(response.body).to include("User")
        expect(response.body).to include("Agent")
      end

      it "renders tool call entry with tool name" do
        get timeline_session_path(session)
        expect(response.body).to include(tool_exec.tool.name)
        expect(response.body).to include("completed")
      end

      it "renders tool output in expandable details" do
        get timeline_session_path(session)
        expect(response.body).to include("file1.txt")
      end

      it "renders LLM usage entry" do
        get timeline_session_path(session)
        expect(response.body).to include(usage.llm_model)
        expect(response.body).to include("200")  # input tokens
      end

      it "includes session cost totals in footer" do
        get timeline_session_path(session)
        expect(response.body).to include("Total cost")
      end
    end

    context "unauthenticated" do
      before { sign_out user }

      it "redirects to login" do
        get timeline_session_path(session)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
