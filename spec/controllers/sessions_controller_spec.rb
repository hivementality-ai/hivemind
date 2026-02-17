# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:active_session1) { create(:session, status: :active, last_activity_at: 2.hours.ago) }
    let!(:active_session2) { create(:session, status: :active, last_activity_at: 1.hour.ago) }
    let!(:inactive_session) { create(:session, status: :completed) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @sessions with active sessions ordered by last activity' do
      get :index
      sessions = assigns(:sessions)
      expect(sessions).to include(active_session1, active_session2)
      expect(sessions).not_to include(inactive_session)
      expect(sessions.first).to eq(active_session2) # Most recent first
    end

    it 'limits results to 50 sessions' do
      # Create more than 50 sessions
      55.times { create(:session, status: :active) }
      get :index
      expect(assigns(:sessions).count).to eq(50)
    end

    it 'includes agent association' do
      get :index
      expect(assigns(:sessions).first.association(:agent)).to be_loaded
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
    context 'with valid agent' do
      it 'creates a new session' do
        expect {
          post :create, params: { agent_id: agent.slug }
        }.to change(Session, :count).by(1)
      end

      it 'sets the correct session attributes' do
        post :create, params: { agent_id: agent.slug }
        new_session = Session.last
        expect(new_session.agent).to eq(agent)
        expect(new_session.session_key).to be_present
        expect(new_session.status).to eq("active")
        expect(new_session.transcript).to eq([])
        expect(new_session.metadata["started_by"]).to eq(user.id)
        expect(new_session.last_activity_at).to be_present
      end

      it 'generates a unique session key' do
        post :create, params: { agent_id: agent.slug }
        new_session = Session.last
        expect(new_session.session_key).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end

      it 'redirects to the new session' do
        post :create, params: { agent_id: agent.slug }
        new_session = Session.last
        expect(response).to redirect_to(session_path(new_session))
      end
    end

    context 'with invalid agent' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          post :create, params: { agent_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :create, params: { agent_id: agent.slug }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #show' do
    let!(:attachment1) { create(:chat_attachment, session: session, message_index: 0) }
    let!(:attachment2) { create(:chat_attachment, session: session, message_index: 1) }

    before do
      # Set up transcript with some messages
      session.update!(transcript: [
        { "role" => "user", "content" => "Hello" },
        { "role" => "assistant", "content" => "Hi there!" },
        { "role" => "user", "content" => "How are you?" }
      ])
    end

    it 'returns a successful response' do
      get :show, params: { id: session.id }
      expect(response).to be_successful
    end

    it 'assigns @agent' do
      get :show, params: { id: session.id }
      expect(assigns(:agent)).to eq(agent)
    end

    it 'assigns @messages from transcript' do
      get :show, params: { id: session.id }
      messages = assigns(:messages)
      expect(messages).to eq(session.transcript)
      expect(messages.length).to eq(3)
    end

    it 'assigns @attachments indexed by message_index' do
      get :show, params: { id: session.id }
      attachments = assigns(:attachments)
      expect(attachments).to be_a(Hash)
      expect(attachments[0]).to eq(attachment1)
      expect(attachments[1]).to eq(attachment2)
    end

    context 'when session has no transcript' do
      before do
        session.update!(transcript: nil)
      end

      it 'assigns empty array for @messages' do
        get :show, params: { id: session.id }
        expect(assigns(:messages)).to eq([])
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show, params: { id: session.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #message' do
    let(:message_content) { "Hello assistant!" }

    context 'with valid message' do
      it 'enqueues ChatStreamJob' do
        expect {
          post :message, params: { id: session.id, message: message_content }
        }.to have_enqueued_job(ChatStreamJob).with(session.id, message_content, [])
      end

      it 'returns ok status' do
        post :message, params: { id: session.id, message: message_content }
        expect(response).to have_http_status(:ok)
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

      it 'creates chat attachments for uploaded files' do
        expect {
          post :message, params: {
            id: session.id,
            message: message_content,
            images: [ image_file ],
            files: [ document_file ]
          }
        }.to change(ChatAttachment, :count).by(2)
      end

      it 'enqueues job with attachment IDs' do
        post :message, params: {
          id: session.id,
          message: message_content,
          images: [ image_file ]
        }

        attachment = ChatAttachment.last
        expect(ChatStreamJob).to have_been_enqueued.with(session.id, message_content, [ attachment.id ])
      end

      it 'sets correct attachment attributes' do
        post :message, params: {
          id: session.id,
          message: message_content,
          images: [ image_file ]
        }

        attachment = ChatAttachment.last
        expect(attachment.session).to eq(session)
        expect(attachment.content_type).to eq('image/png')
        expect(attachment.filename).to eq('test_image.png')
        expect(attachment.file).to be_attached
      end

      it 'allows message with only attachments and no text' do
        expect {
          post :message, params: {
            id: session.id,
            images: [ image_file ]
          }
        }.to change(ChatAttachment, :count).by(1)
      end
    end

    context 'with blank message and no attachments' do
      it 'returns unprocessable entity status' do
        post :message, params: { id: session.id, message: "   " }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not enqueue job' do
        expect {
          post :message, params: { id: session.id, message: "" }
        }.not_to have_enqueued_job(ChatStreamJob)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :message, params: { id: session.id, message: message_content }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
