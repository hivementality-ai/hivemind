# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLogsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  describe 'GET #index' do
    context 'with no logs' do
      it 'returns a successful response' do
        get :index
        expect(response).to be_successful
      end

      it 'assigns empty logs' do
        get :index
        expect(assigns(:logs).to_a).to eq([])
      end
    end

    context 'with existing audit logs' do
      let!(:agent_log)  { create(:audit_log, actor_type: 'agent',  actor_id: '1', action: 'session.start', created_at: 1.hour.ago) }
      let!(:user_log)   { create(:audit_log, actor_type: 'user',   actor_id: '2', action: 'vault.read',    created_at: 2.hours.ago) }
      let!(:system_log) { create(:audit_log, actor_type: 'system', actor_id: 'system', action: 'startup',  created_at: 3.hours.ago) }

      it 'returns a successful response' do
        get :index
        expect(response).to be_successful
      end

      it 'assigns logs ordered most-recent first' do
        get :index
        logs = assigns(:logs).to_a
        expect(logs.first.created_at).to be > logs.last.created_at
      end

      it 'assigns total_count' do
        get :index
        expect(assigns(:total_count)).to eq(3)
      end

      it 'assigns actor_types list' do
        get :index
        expect(assigns(:actor_types)).to eq(%w[agent user system])
      end

      it 'assigns distinct_actions' do
        get :index
        expect(assigns(:distinct_actions)).to include('session.start', 'startup', 'vault.read')
      end

      describe 'filtering by actor_type' do
        it 'returns only logs for that actor type' do
          get :index, params: { actor_type: 'agent' }
          logs = assigns(:logs).to_a
          expect(logs).to include(agent_log)
          expect(logs).not_to include(user_log)
          expect(logs).not_to include(system_log)
        end

        it 'ignores disallowed actor_type values' do
          get :index, params: { actor_type: 'hacker' }
          expect(assigns(:logs).to_a.length).to eq(3)
        end
      end

      describe 'filtering by actor_type and actor_id' do
        it 'returns only logs for that specific actor' do
          get :index, params: { actor_type: 'agent', actor_id: '1' }
          logs = assigns(:logs).to_a
          expect(logs).to eq([agent_log])
        end
      end

      describe 'filtering by action' do
        it 'returns only logs matching the action' do
          get :index, params: { action_filter: 'vault.read' }
          logs = assigns(:logs).to_a
          expect(logs).to eq([user_log])
        end
      end

      describe 'filtering by date range' do
        it 'respects the from date' do
          get :index, params: { from: 1.5.hours.ago.to_date.to_s }
          logs = assigns(:logs).to_a
          expect(logs).to include(agent_log)
          expect(logs).not_to include(system_log)
        end

        it 'ignores unparseable from date' do
          expect {
            get :index, params: { from: 'not-a-date' }
          }.not_to raise_error
          expect(assigns(:total_count)).to eq(3)
        end
      end

      describe 'pagination' do
        before do
          stub_const("AuditLogsController::PER_PAGE", 2)
        end

        it 'defaults to page 1' do
          get :index
          expect(assigns(:page)).to eq(1)
        end

        it 'limits results to PER_PAGE' do
          get :index
          expect(assigns(:logs).to_a.length).to eq(2)
        end

        it 'calculates total_pages correctly' do
          get :index
          expect(assigns(:total_pages)).to eq(2)
        end

        it 'returns the correct page when specified' do
          get :index, params: { page: 2 }
          expect(assigns(:logs).to_a.length).to eq(1)
        end

        it 'treats page 0 or negative as page 1' do
          get :index, params: { page: 0 }
          expect(assigns(:page)).to eq(1)
        end
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
end
