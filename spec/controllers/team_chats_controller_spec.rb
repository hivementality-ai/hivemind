# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamChatsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:team) { create(:team) }
  let(:agent) { create(:agent, team: team) }
  let(:team_chat_session) { create(:team_chat_session, team: team, user: user) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #create' do
    context 'with valid team' do
      it 'creates a new team chat session' do
        expect {
          post :create, params: { team_id: team.id }
        }.to change(TeamChatSession, :count).by(1)
      end

      it 'sets the correct attributes' do
        post :create, params: { team_id: team.id }
        session = TeamChatSession.last
        expect(session.team).to eq(team)
        expect(session.user).to eq(user)
        expect(session.title).to eq("#{team.name} Chat")
      end

      it 'redirects to the new team chat session' do
        post :create, params: { team_id: team.id }
        session = TeamChatSession.last
        expect(response).to redirect_to(team_chat_path(session))
      end
    end

    context 'with invalid team' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          post :create, params: { team_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :create, params: { team_id: team.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #show' do
    let!(:agent1) { create(:agent, team: team, name: "Alpha", enabled: true) }
    let!(:agent2) { create(:agent, team: team, name: "Beta", enabled: true) }
    let!(:disabled_agent) { create(:agent, team: team, name: "Gamma", enabled: false) }
    let!(:message1) { create(:team_chat_message, team_chat_session: team_chat_session) }
    let!(:message2) { create(:team_chat_message, team_chat_session: team_chat_session) }

    it 'returns a successful response' do
      get :show, params: { id: team_chat_session.id }
      expect(response).to be_successful
    end

    it 'assigns @team' do
      get :show, params: { id: team_chat_session.id }
      expect(assigns(:team)).to eq(team)
    end

    it 'assigns @agents with enabled agents ordered by name' do
      get :show, params: { id: team_chat_session.id }
      agents = assigns(:agents)
      expect(agents.map(&:name)).to eq(%w[Alpha Beta])
      expect(agents).not_to include(disabled_agent)
    end

    it 'assigns @messages' do
      get :show, params: { id: team_chat_session.id }
      expect(assigns(:messages)).to be_present
    end

    it 'assigns @past_sessions' do
      other_session = create(:team_chat_session, team: team)
      get :show, params: { id: team_chat_session.id }
      expect(assigns(:past_sessions)).to be_present
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show, params: { id: team_chat_session.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #message' do
    let(:message_content) { "Hello team!" }

    context 'with valid message' do
      it 'creates a new team chat message' do
        expect {
          post :message, params: { id: team_chat_session.id, message: message_content }
        }.to change(TeamChatMessage, :count).by(1)
      end

      it 'sets the correct message attributes' do
        post :message, params: { id: team_chat_session.id, message: message_content }
        message = TeamChatMessage.last
        expect(message.sender_type).to eq("user")
        expect(message.sender_id).to eq(user.id)
        expect(message.content).to eq(message_content)
        expect(message.team_chat_session).to eq(team_chat_session)
      end

      it 'returns ok status' do
        post :message, params: { id: team_chat_session.id, message: message_content }
        expect(response).to have_http_status(:ok)
      end

      it 'touches the session to update last activity' do
        expect {
          post :message, params: { id: team_chat_session.id, message: message_content }
        }.to change { team_chat_session.reload.updated_at }
      end

      context 'with @mention for specific agent' do
        let(:mentioned_agent) { create(:agent, team: team, name: "SpecificAgent") }
        let(:message_with_mention) { "@SpecificAgent please help" }

        it 'sets target_agent_id when mentioning specific agent' do
          post :message, params: { id: team_chat_session.id, message: message_with_mention }
          message = TeamChatMessage.last
          expect(message.target_agent_id).to eq(mentioned_agent.id)
        end
      end
    end

    context 'with file attachments' do
      let(:image_file) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png'), 'image/png') }
      let(:document_file) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_document.txt'), 'text/plain') }

      before do
        # Create the fixture files directory if it doesn't exist
        FileUtils.mkdir_p(Rails.root.join('spec', 'fixtures', 'files'))
        File.write(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png'), 'fake png content')
        File.write(Rails.root.join('spec', 'fixtures', 'files', 'test_document.txt'), 'test document content')
      end

      it 'creates message with image attachment' do
        post :message, params: { 
          id: team_chat_session.id, 
          message: "Check this image",
          images: [image_file] 
        }
        
        message = TeamChatMessage.last
        expect(message.images).to be_attached
        expect(message.images.count).to eq(1)
      end

      it 'creates message with document attachment' do
        post :message, params: { 
          id: team_chat_session.id, 
          message: "Check this document",
          files: [document_file] 
        }
        
        message = TeamChatMessage.last
        expect(message.documents).to be_attached
        expect(message.documents.count).to eq(1)
      end

      it 'allows message with only attachments and no text' do
        expect {
          post :message, params: { 
            id: team_chat_session.id, 
            images: [image_file] 
          }
        }.to change(TeamChatMessage, :count).by(1)
      end
    end

    context 'with blank message and no attachments' do
      it 'returns unprocessable entity status' do
        post :message, params: { id: team_chat_session.id, message: "   " }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not create a message' do
        expect {
          post :message, params: { id: team_chat_session.id, message: "" }
        }.not_to change(TeamChatMessage, :count)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :message, params: { id: team_chat_session.id, message: message_content }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end