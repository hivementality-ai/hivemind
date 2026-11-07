# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavedPages::AutoSave do
  let(:agent) { create(:agent) }
  let(:long_text) { "# Findings\n\n#{'word ' * ((SavedPage::AUTO_SAVE_MIN_CHARS / 5) + 10)}" }

  describe ".research" do
    let(:session) { create(:session, agent: agent) }
    let(:research) { create(:research_session, :completed, agent: agent, session: session, query: "Battery chemistry") }

    it "saves a long report as a research page and returns it" do
      page = described_class.research(research, long_text)

      expect(page).to have_attributes(source_kind: "research", agent: agent, session: session, research_session: research, body: long_text)
    end

    it "leaves a short report alone" do
      expect(described_class.research(research, "Short.")).to be_nil
      expect(SavedPage.count).to eq(0)
    end

    it "does not save the same research twice" do
      first = described_class.research(research, long_text)

      expect { described_class.research(research, long_text) }.not_to change(SavedPage, :count)
      expect(described_class.research(research, long_text)).to eq(first)
    end
  end

  describe ".scheduled" do
    let(:session) do
      create(:session, agent: agent, title: "Scheduled: Monday digest", metadata: { "type" => "scheduled", "scheduled_task_id" => 1 })
    end

    it "saves a long answer and adds a link to it at the end" do
      result = described_class.scheduled(session, long_text)

      page = SavedPage.last
      expect(page).to have_attributes(source_kind: "scheduled", session: session, agent: agent, body: long_text)
      expect(result).to start_with(long_text)
      expect(result).to end_with("\n\n[Open the saved page](/pages/#{page.id})")
    end

    it "returns a short answer untouched" do
      expect(described_class.scheduled(session, "All quiet.")).to eq("All quiet.")
      expect(SavedPage.count).to eq(0)
    end

    it "ignores chats that are not scheduled runs" do
      plain = create(:session, agent: agent)
      expect(described_class.scheduled(plain, long_text)).to eq(long_text)
      expect(SavedPage.count).to eq(0)
    end

    it "returns the answer untouched if saving fails" do
      allow(SavedPage).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect(described_class.scheduled(session, long_text)).to eq(long_text)
    end
  end
end
