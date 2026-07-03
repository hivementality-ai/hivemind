# frozen_string_literal: true

require "rails_helper"

RSpec.describe "KnowledgeDocuments", type: :request do
  let(:agent) { create(:agent) }
  let(:owner) { create(:user, :owner) }
  let(:viewer) { create(:user, :viewer) }
  let!(:doc) { create(:knowledge_document, agent: agent, title: "Test Doc", source_type: "text") }

  describe "GET /knowledge" do
    context "as owner" do
      before { sign_in owner }

      it "lists documents" do
        get knowledge_documents_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Test Doc")
      end
    end

    context "as viewer" do
      before { sign_in viewer }

      it "is accessible (read-only)" do
        get knowledge_documents_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /knowledge/:id" do
    before { sign_in owner }

    it "shows document details" do
      get knowledge_document_path(doc)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test Doc")
    end
  end

  describe "POST /knowledge" do
    context "as owner" do
      before { sign_in owner }

      it "creates a text document and enqueues ingestion job" do
        file = Tempfile.new([ "kb", ".txt" ])
        file.write("hello world")
        file.close

        expect {
          post knowledge_documents_path, params: {
            knowledge_document: {
              title: "New Doc",
              agent_id: agent.id,
              source_type: "text",
              text_content: "some knowledge content"
            }
          }
        }.to have_enqueued_job(KnowledgeIngestionJob)

        expect(response).to redirect_to(knowledge_documents_path)
        expect(KnowledgeDocument.find_by(title: "New Doc")).to be_present
      ensure
        file.unlink
      end
    end

    context "as viewer" do
      before { sign_in viewer }

      it "denies access" do
        post knowledge_documents_path, params: {
          knowledge_document: {
            title: "Denied",
            agent_id: agent.id,
            source_type: "text",
            text_content: "content"
          }
        }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "DELETE /knowledge/:id" do
    context "as owner" do
      before { sign_in owner }

      it "destroys the document and its chunks" do
        create(:knowledge_chunk, knowledge_document: doc, agent: agent)

        expect {
          delete knowledge_document_path(doc)
        }.to change(KnowledgeDocument, :count).by(-1)
           .and change(KnowledgeChunk, :count).by(-1)

        expect(response).to redirect_to(knowledge_documents_path)
      end
    end

    context "as viewer" do
      before { sign_in viewer }

      it "denies access" do
        delete knowledge_document_path(doc)
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
