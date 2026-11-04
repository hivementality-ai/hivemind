# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CustomScriptExecutor do
  let(:agent) { create(:agent) }

  def run(config)
    described_class.new(input: {}, config: config, agent: agent).call
  end

  before do
    allow(Open3).to receive(:capture3) do |env, *_args, **_opts|
      [ "token=#{env['STRIPE_API_KEY']}", "", instance_double(Process::Status, exitstatus: 0) ]
    end
  end

  it "injects vault secrets into the script environment and redacts them from output" do
    create(:vault_entry, namespace: "stripe", key: "api_key", value: "sk-test-abcdef1234")

    result = run("script_template" => "echo $STRIPE_API_KEY", "secret_refs" => { "STRIPE_API_KEY" => "vault:stripe/api_key" })

    expect(Open3).to have_received(:capture3).with(hash_including("STRIPE_API_KEY" => "sk-test-abcdef1234"), any_args)
    expect(result.data[:output]).to eq("token=[REDACTED]")
  end

  it "fails without running when a referenced secret is gone" do
    result = run("script_template" => "echo hi", "secret_refs" => { "STRIPE_API_KEY" => "vault:stripe/gone" })

    expect(result).not_to be_success
    expect(result.error).to include("STRIPE_API_KEY")
    expect(Open3).not_to have_received(:capture3)
  end

  it "runs tools without secrets as before" do
    expect(run("script_template" => "echo hi")).to be_success
  end
end
