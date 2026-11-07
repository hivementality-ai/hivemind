# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SavePageExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:input) { { "title" => "Competitor notes", "body" => "# Notes\n\nThey raised a round." } }

  def run(input, config: { session: session })
    described_class.new(input: input, config: config, agent: agent).call
  end

  it "saves a page for the agent and tells it where the page lives" do
    result = nil
    expect { result = run(input) }.to change(SavedPage, :count).by(1)

    page = SavedPage.last
    expect(page).to have_attributes(title: "Competitor notes", body: input["body"], agent: agent, session: session, source_kind: "chat", created_by: nil)
    expect(result).to be_success
    expect(result.data[:output]).to include("/pages/#{page.id}")
  end

  it "makes up a title when none is given" do
    run({ "body" => "## Pricing changes\n\nUp 10%." })
    expect(SavedPage.last.title).to eq("Pricing changes")
  end

  it "marks pages saved during a scheduled run as scheduled" do
    scheduled = create(:session, agent: agent, metadata: { "type" => "scheduled" })
    run(input, config: { session: scheduled })
    expect(SavedPage.last.source_kind).to eq("scheduled")
  end

  it "works without a chat" do
    run(input, config: {})
    expect(SavedPage.last.session).to be_nil
  end

  it "refuses an empty body" do
    expect(run({ "title" => "x", "body" => " " })).not_to be_success
    expect(SavedPage.count).to eq(0)
  end

  it "needs an agent" do
    result = described_class.new(input: input, config: {}, agent: nil).call
    expect(result).not_to be_success
  end

  it "is registered as the save_page tool" do
    expect(Tools::Executor.all_executors["save_page"]).to eq(described_class)
  end
end
