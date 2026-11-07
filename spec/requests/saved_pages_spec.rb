# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Saved pages", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:agent) { create(:agent) }

  describe "signed out" do
    it "sends visitors to sign in" do
      get saved_pages_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "reading" do
    let(:viewer) { create(:user, :viewer) }

    before { sign_in viewer }

    it "lists pages newest first" do
      create(:saved_page, title: "Older page", created_at: 3.days.ago)
      create(:saved_page, title: "Newer page", created_at: 1.hour.ago)

      get saved_pages_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Newer page")).to be < response.body.index("Older page")
    end

    it "searches by title" do
      create(:saved_page, title: "Sales review")
      create(:saved_page, title: "Hiring plan")

      get saved_pages_path, params: { q: "sales" }

      expect(response.body).to include("Sales review")
      expect(response.body).not_to include("Hiring plan")
    end

    it "says so when nothing matches" do
      get saved_pages_path, params: { q: "zzz" }
      expect(response.body).to include("No pages match that.")
    end

    it "shows an empty list in plain words" do
      get saved_pages_path
      expect(response.body).to include("Nothing saved yet")
    end

    it "shows a page with its markdown handed to the browser renderer" do
      page = create(:saved_page, title: "Digest", body: "# Digest\n\nSee [Handbook, p. 4] for details.")

      get saved_page_path(page)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"markdown\"")
      expect(response.body).to include("See [Handbook, p. 4] for details.")
    end

    it "never puts a script from the body into the page as markup" do
      page = create(:saved_page, body: "Hello <script>alert('x')</script> <img src=x onerror=alert(1)>")

      get saved_page_path(page)

      expect(response.body).not_to include("<script>alert")
      expect(response.body).not_to include("<img src=x")
      expect(response.body).to include("&lt;script&gt;alert")
    end

    it "keeps long words from stretching the page on a phone" do
      page = create(:saved_page)

      get saved_page_path(page)

      expect(response.body).to include("break-words")
      expect(response.body).to include("overflow-x-hidden")
    end

    it "links back to the chat the page came from" do
      session = create(:session, agent: agent)
      page = create(:saved_page, agent: agent, session: session)

      get saved_page_path(page)

      expect(response.body).to include(session_path(session))
    end

    it "does not let a viewer save, rename or delete" do
      page = create(:saved_page)

      patch saved_page_path(page), params: { saved_page: { title: "New" } }
      delete saved_page_path(page)

      expect(page.reload.title).not_to eq("New")
      expect(SavedPage.exists?(page.id)).to be(true)
    end
  end

  describe "saving from a chat message" do
    let(:session) do
      create(:session, agent: agent, transcript: [
        { "role" => "user", "content" => "Write the digest" },
        { "role" => "assistant", "content" => "# Monday digest\n\nA long answer." }
      ])
    end

    before { sign_in owner }

    it "keeps the chosen reply as a page and opens it" do
      expect {
        post saved_pages_path, params: { session_id: session.id, message_index: 1 }
      }.to change(SavedPage, :count).by(1)

      page = SavedPage.last
      expect(page).to have_attributes(title: "Monday digest", body: "# Monday digest\n\nA long answer.", agent: agent, session: session, created_by: owner, source_kind: "chat")
      expect(response).to redirect_to(saved_page_path(page))
    end

    it "refuses to save a message that is not from the assistant" do
      expect {
        post saved_pages_path, params: { session_id: session.id, message_index: 0 }
      }.not_to change(SavedPage, :count)
      expect(response).to redirect_to(session_path(session))
    end

    it "refuses a message that does not exist" do
      expect {
        post saved_pages_path, params: { session_id: session.id, message_index: 9 }
      }.not_to change(SavedPage, :count)
    end

    it "refuses an index that is not a plain number" do
      expect {
        post saved_pages_path, params: { session_id: session.id, message_index: "1abc" }
      }.not_to change(SavedPage, :count)
      expect(response).to redirect_to(session_path(session))
    end

    it "marks pages from scheduled runs as scheduled" do
      session.update!(metadata: { "type" => "scheduled" })
      post saved_pages_path, params: { session_id: session.id, message_index: 1 }
      expect(SavedPage.last.source_kind).to eq("scheduled")
    end

    it "is not open to viewers" do
      sign_in create(:user, :viewer)
      expect {
        post saved_pages_path, params: { session_id: session.id, message_index: 1 }
      }.not_to change(SavedPage, :count)
    end

    it "adds a Save as page button to each assistant reply in the chat" do
      get session_path(session)
      expect(response.body).to include("Save as page")
      expect(response.body).to include("message_index")
    end
  end

  describe "renaming and deleting" do
    let!(:page) { create(:saved_page, title: "Draft title") }

    before { sign_in owner }

    it "changes only the title" do
      patch saved_page_path(page), params: { saved_page: { title: "Final title", body: "hacked" } }

      page.reload
      expect(page.title).to eq("Final title")
      expect(page.body).not_to eq("hacked")
      expect(response).to redirect_to(saved_page_path(page))
    end

    it "keeps the old title and says why when the new one is blank" do
      patch saved_page_path(page), params: { saved_page: { title: " " } }

      expect(page.reload.title).to eq("Draft title")
      expect(flash[:alert]).to be_present
    end

    it "asks for confirmation before deleting" do
      get saved_page_path(page)
      expect(response.body).to include("data-turbo-confirm")
    end

    it "deletes the page" do
      expect { delete saved_page_path(page) }.to change(SavedPage, :count).by(-1)
      expect(response).to redirect_to(saved_pages_path)
    end

    it "lets the person who saved a page delete it, but not other operators" do
      mine = create(:user, :operator)
      theirs = create(:saved_page, created_by: mine)

      sign_in create(:user, :operator)
      expect { delete saved_page_path(theirs) }.not_to change(SavedPage, :count)

      sign_in mine
      expect { delete saved_page_path(theirs) }.to change(SavedPage, :count).by(-1)
    end
  end

  describe "sidebar" do
    it "links to Pages" do
      sign_in owner
      get saved_pages_path
      expect(response.body).to include("href=\"#{saved_pages_path}\"", "<span>Pages</span>")
    end
  end
end
