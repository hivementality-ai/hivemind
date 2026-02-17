# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentChannelsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:channel) { create(:channel) }
  let(:agent) { create(:agent) }

  before { sign_in user }

  describe 'POST #create' do
    let(:valid_params) { { channel_id: channel.id, agent_channel: { agent_id: agent.id, is_default: true } } }

    it 'creates an agent channel and redirects' do
      expect {
        post :create, params: valid_params
      }.to change(AgentChannel, :count).by(1)
      expect(response).to redirect_to(edit_channel_path(channel))
      expect(flash[:notice]).to include('configured successfully')
    end

    context 'with invalid params' do
      it 'redirects with alert on failure' do
        post :create, params: { channel_id: channel.id, agent_channel: { agent_id: nil } }
        expect(response).to redirect_to(edit_channel_path(channel))
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :create, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    let!(:agent_channel) { create(:agent_channel, channel: channel, agent: agent) }

    it 'updates and redirects with notice' do
      patch :update, params: { channel_id: channel.id, id: agent_channel.id, agent_channel: { is_default: true } }
      expect(response).to redirect_to(edit_channel_path(channel))
      expect(flash[:notice]).to include('updated successfully')
    end

    context 'with invalid params' do
      it 'redirects with alert on failure' do
        allow_any_instance_of(AgentChannel).to receive(:update).and_return(false)
        allow_any_instance_of(AgentChannel).to receive(:errors).and_return(double(full_messages: [ 'Error' ]))
        patch :update, params: { channel_id: channel.id, id: agent_channel.id, agent_channel: { agent_id: nil } }
        expect(response).to redirect_to(edit_channel_path(channel))
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:agent_channel) { create(:agent_channel, channel: channel, agent: agent) }

    it 'destroys and redirects with notice' do
      expect {
        delete :destroy, params: { channel_id: channel.id, id: agent_channel.id }
      }.to change(AgentChannel, :count).by(-1)
      expect(response).to redirect_to(edit_channel_path(channel))
      expect(flash[:notice]).to include('removed successfully')
    end

    context 'when destroy raises error' do
      it 'redirects with alert' do
        allow_any_instance_of(AgentChannel).to receive(:destroy!).and_raise(StandardError, 'boom')
        delete :destroy, params: { channel_id: channel.id, id: agent_channel.id }
        expect(response).to redirect_to(edit_channel_path(channel))
        expect(flash[:alert]).to include('boom')
      end
    end
  end
end
