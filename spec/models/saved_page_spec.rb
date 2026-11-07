# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavedPage, type: :model do
  it "is valid from the factory" do
    expect(build(:saved_page)).to be_valid
  end

  it "needs a title and a body" do
    expect(build(:saved_page, title: "")).not_to be_valid
    expect(build(:saved_page, body: "  ")).not_to be_valid
  end

  it "only accepts known source kinds" do
    expect(build(:saved_page, source_kind: "email")).not_to be_valid
    expect(build(:saved_page, source_kind: "scheduled")).to be_valid
  end

  it "keeps the page when its chat is deleted" do
    session = create(:session)
    page = create(:saved_page, session: session)
    session.destroy!
    expect(page.reload.session_id).to be_nil
  end

  describe ".newest_first" do
    it "orders by creation time, newest first" do
      old = create(:saved_page, created_at: 2.days.ago)
      fresh = create(:saved_page, created_at: 1.hour.ago)
      expect(described_class.newest_first).to eq([ fresh, old ])
    end
  end

  describe ".search_title" do
    it "matches part of a title, ignoring case and LIKE wildcards" do
      match = create(:saved_page, title: "Quarterly Sales Review")
      create(:saved_page, title: "Hiring plan")
      percent = create(:saved_page, title: "100% done")

      expect(described_class.search_title("sales")).to eq([ match ])
      expect(described_class.search_title("%")).to eq([ percent ])
      expect(described_class.search_title("")).to match_array(described_class.all)
    end
  end

  describe ".title_from" do
    it "uses the first heading" do
      expect(described_class.title_from("Intro line\n\n## The big picture\nText")).to eq("The big picture")
    end

    it "falls back to the first line with markdown marks removed" do
      expect(described_class.title_from("**Done** with the report\nmore")).to eq("Done with the report")
    end

    it "shortens long lines and names empty bodies" do
      expect(described_class.title_from("a" * 300).length).to be <= SavedPage::TITLE_LIMIT
      expect(described_class.title_from("  \n ")).to eq("Untitled page")
    end
  end
end
