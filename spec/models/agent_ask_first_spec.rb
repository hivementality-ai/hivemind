# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent, "ask first switches" do
  let(:agent) { create(:agent) }

  it "asks about every category by default" do
    Approvals::AskFirst::CATEGORIES.each_key { |category| expect(agent.asks_first?(category)).to be(true) }
  end

  it "turns one category off and back on" do
    agent.update!(ask_first: { "send_email" => "0" })
    expect(agent.reload.asks_first?("send_email")).to be(false)
    expect(agent.asks_first?("delete_file")).to be(true)

    agent.update!(ask_first: { "send_email" => "1" })
    expect(agent.reload.asks_first?("send_email")).to be(true)
  end

  it "ignores categories it does not know" do
    agent.update!(ask_first: { "launch_missiles" => "0" })

    expect(agent.reload.ask_first_overrides).to eq({})
  end
end
