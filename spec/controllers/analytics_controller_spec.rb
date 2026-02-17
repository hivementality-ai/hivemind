# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let(:mock_response) do
      double(:response,
        success?: true,
        data: {
          summary: { total_cost: 100.50, total_sessions: 10 },
          per_agent: [ { name: "Agent 1", cost: 50.25 } ],
          agents: [ agent ]
        }
      )
    end

    before do
      allow(Analytics::TeamSummary).to receive(:call).and_return(mock_response)
    end

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'calls Analytics::TeamSummary with default period' do
      expect(Analytics::TeamSummary).to receive(:call).with(period: "week")
      get :index
    end

    it 'calls Analytics::TeamSummary with specified period' do
      expect(Analytics::TeamSummary).to receive(:call).with(period: "month")
      get :index, params: { period: "month" }
    end

    it 'assigns analytics data on success' do
      get :index
      expect(assigns(:summary)).to eq({ total_cost: 100.50, total_sessions: 10 })
      expect(assigns(:per_agent)).to eq([ { name: "Agent 1", cost: 50.25 } ])
      expect(assigns(:agents)).to eq([ agent ])
    end

    context 'when analytics service fails' do
      let(:error_response) do
        double(:response, success?: false, error: "Analytics service error")
      end

      before do
        allow(Analytics::TeamSummary).to receive(:call).and_return(error_response)
      end

      it 'assigns empty data and shows error' do
        get :index
        expect(assigns(:summary)).to eq({})
        expect(assigns(:per_agent)).to eq([])
        expect(assigns(:agents)).to eq([])
        expect(flash.now[:alert]).to eq("Analytics service error")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #show' do
    let(:mock_response) do
      double(:response,
        success?: true,
        data: {
          cost_breakdown: { input: 25.50, output: 30.75 },
          session_count: 5,
          avg_session_cost: 11.25
        }
      )
    end

    before do
      allow(Analytics::AgentSummary).to receive(:call).and_return(mock_response)
    end

    it 'returns a successful response' do
      get :show, params: { id: agent.slug }
      expect(response).to be_successful
    end

    it 'assigns @agent' do
      get :show, params: { id: agent.slug }
      expect(assigns(:agent)).to eq(agent)
    end

    it 'calls Analytics::AgentSummary with agent and period' do
      expect(Analytics::AgentSummary).to receive(:call).with(agent: agent, period: "week")
      get :show, params: { id: agent.slug }
    end

    it 'calls Analytics::AgentSummary with specified period' do
      expect(Analytics::AgentSummary).to receive(:call).with(agent: agent, period: "day")
      get :show, params: { id: agent.slug, period: "day" }
    end

    it 'assigns analytics data on success' do
      get :show, params: { id: agent.slug }
      analytics = assigns(:analytics)
      expect(analytics[:cost_breakdown]).to eq({ input: 25.50, output: 30.75 })
      expect(analytics[:session_count]).to eq(5)
      expect(analytics[:avg_session_cost]).to eq(11.25)
    end

    context 'when analytics service fails' do
      let(:error_response) do
        double(:response, success?: false, error: "Agent analytics error")
      end

      before do
        allow(Analytics::AgentSummary).to receive(:call).and_return(error_response)
      end

      it 'assigns empty data and shows error' do
        get :show, params: { id: agent.slug }
        expect(assigns(:analytics)).to eq({})
        expect(flash.now[:alert]).to eq("Agent analytics error")
      end
    end

    context 'with invalid agent' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show, params: { id: agent.slug }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
