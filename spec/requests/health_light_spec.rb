# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health light", type: :request do
  let(:user) { create(:user) }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    sign_in user
  end

  it "renders an amber light and the plain-English list from the cache" do
    store.write(Platform::HealthLight::CACHE_KEY, {
      status: :amber,
      checks: [
        { key: "claude", label: "Claude", ok: true, detail: "working", critical: true },
        { key: "studio", label: "Studio brain", ok: false, detail: "not reachable", critical: false }
      ],
      checked_at: Time.current
    })

    get agents_path

    expect(response.body).to include('data-testid="health-light"', 'data-status="amber"')
    expect(response.body).to include("Claude: working", "Studio brain: not reachable")
  end

  it "renders a neutral light before the first check has run" do
    get agents_path

    expect(response.body).to include('data-status="unknown"', "First check is running.")
  end
end
