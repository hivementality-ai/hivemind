# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ComposioExecutor do
  let(:agent) { create(:agent) }
  let(:base) { "https://backend.composio.dev/api/v3" }

  def stub_vault(pairs)
    allow(VaultEntry).to receive(:find_by) do |namespace:, key:|
      val = pairs[[ namespace, key ]]
      val && double(value: val)
    end
  end

  def execute(input)
    described_class.new(input: input, config: {}, agent: agent).call
  end

  before { stub_vault({ [ "composio", "api_key" ] => "ak_test" }) }

  it "fails when the API key is not configured" do
    stub_vault({})
    result = execute("action" => "list_toolkits")
    expect(result.success?).to be(false)
    expect(result.error).to include("API key not configured")
  end

  it "requires tool_slug for execute" do
    result = execute("action" => "execute")
    expect(result.success?).to be(false)
    expect(result.error).to include("tool_slug is required")
  end

  it "executes a tool with the x-api-key header" do
    stub = stub_request(:post, "#{base}/tools/execute/GITHUB_CREATE_AN_ISSUE")
      .with(headers: { "x-api-key" => "ak_test" }, body: { arguments: { title: "hi" }, user_id: "u1" }.to_json)
      .to_return(status: 200, body: { data: { id: 9 } }.to_json)

    result = execute(
      "action" => "execute", "tool_slug" => "GITHUB_CREATE_AN_ISSUE",
      "arguments" => { "title" => "hi" }, "user_id" => "u1"
    )

    expect(result.success?).to be(true)
    expect(result.data[:output]).to include("\"id\"")
    expect(stub).to have_been_requested
  end

  it "lists tools filtered by toolkit" do
    stub = stub_request(:get, "#{base}/tools").with(query: { "toolkit_slug" => "github" })
      .to_return(status: 200, body: "[]")

    result = execute("action" => "list_tools", "toolkit" => "github")
    expect(result.success?).to be(true)
    expect(stub).to have_been_requested
  end

  it "surfaces HTTP errors" do
    stub_request(:get, "#{base}/toolkits").to_return(status: 403, body: { error: "forbidden" }.to_json)

    result = execute("action" => "list_toolkits")
    expect(result.success?).to be(false)
    expect(result.error).to include("HTTP 403")
  end
end
