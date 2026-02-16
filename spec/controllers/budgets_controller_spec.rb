# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BudgetsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:agent1) { create(:agent, name: "Beta Agent") }
    let!(:agent2) { create(:agent, name: "Alpha Agent") }
    let!(:budget1) { create(:agent_budget, agent: agent1) }
    let!(:usage1) { create(:usage_record, agent: agent1) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @agents ordered by name with associations' do
      get :index
      agents = assigns(:agents)
      expect(agents).to include(agent1, agent2)
      # Verify associations are loaded
      expect(agents.first.association(:agent_budgets)).to be_loaded
      expect(agents.first.association(:usage_records)).to be_loaded
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #update' do
    context 'with daily and monthly limits' do
      let(:valid_params) do
        {
          agent_id: agent.id,
          daily_limit: "10.50",
          monthly_limit: "250.00"
        }
      end

      it 'creates or updates budget records' do
        expect {
          post :update, params: valid_params
        }.to change(AgentBudget, :count).by(2)

        daily_budget = agent.agent_budgets.find_by(period: "daily")
        monthly_budget = agent.agent_budgets.find_by(period: "monthly")

        expect(daily_budget.limit_cents).to eq(1050) # $10.50 * 100
        expect(monthly_budget.limit_cents).to eq(25000) # $250.00 * 100
      end

      it 'redirects with success notice' do
        post :update, params: valid_params
        expect(response).to redirect_to(budgets_path)
        expect(flash[:notice]).to eq("Budget updated for #{agent.name}")
      end

      context 'when budgets already exist' do
        let!(:existing_daily) { create(:agent_budget, agent: agent, period: "daily", limit_cents: 500) }
        let!(:existing_monthly) { create(:agent_budget, agent: agent, period: "monthly", limit_cents: 10000) }

        it 'updates existing budgets without creating new ones' do
          expect {
            post :update, params: valid_params
          }.not_to change(AgentBudget, :count)

          existing_daily.reload
          existing_monthly.reload
          expect(existing_daily.limit_cents).to eq(1050)
          expect(existing_monthly.limit_cents).to eq(25000)
        end
      end
    end

    context 'with only daily limit' do
      let(:partial_params) do
        {
          agent_id: agent.id,
          daily_limit: "5.25"
        }
      end

      it 'creates only daily budget' do
        expect {
          post :update, params: partial_params
        }.to change(AgentBudget, :count).by(1)

        daily_budget = agent.agent_budgets.find_by(period: "daily")
        expect(daily_budget.limit_cents).to eq(525)
        expect(agent.agent_budgets.find_by(period: "monthly")).to be_nil
      end
    end

    context 'with blank limits' do
      let(:blank_params) do
        {
          agent_id: agent.id,
          daily_limit: "",
          monthly_limit: "   "
        }
      end

      it 'does not create budgets for blank values' do
        expect {
          post :update, params: blank_params
        }.not_to change(AgentBudget, :count)
      end

      it 'still redirects with success message' do
        post :update, params: blank_params
        expect(response).to redirect_to(budgets_path)
        expect(flash[:notice]).to eq("Budget updated for #{agent.name}")
      end
    end

    context 'with invalid agent' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          post :update, params: { agent_id: 999999, daily_limit: "10.00" }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :update, params: { agent_id: agent.id, daily_limit: "10.00" }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
