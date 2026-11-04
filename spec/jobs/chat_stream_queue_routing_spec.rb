# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ChatStreamJob queue routing", type: :job do
  include ActiveJob::TestHelper

  def sidekiq_config(name)
    YAML.safe_load(ERB.new(Rails.root.join("config/#{name}").read).result, permitted_classes: [ Symbol ])
  end

  it "defaults to the agents queue for heartbeat, sub-agent and pipeline enqueues" do
    expect(ChatStreamJob.new.queue_name).to eq("agents")
  end

  it "keeps scheduled agent runs on the agents queue" do
    task = create(:scheduled_task, agent: create(:agent), name: "Daily", schedule: "0 9 * * *",
                  job_params: { "prompt" => "status" }, enabled: true)

    expect { ScheduledAgentJob.perform_now(task.id) }
      .to have_enqueued_job(ChatStreamJob).on_queue("agents")
  end

  describe "a user message" do
    let(:chat_session) { create(:session, agent: create(:agent)) }
    let(:host) { Class.new { include SessionChatActions }.new }

    before do
      allow(ActionCable.server).to receive(:broadcast)
      allow(Sessions::ResolvePendingQuestion).to receive(:call).and_return(double(success?: false))
    end

    it "lands on the interactive queue" do
      expect { host.send(:process_chat_message, session: chat_session, message: "hello") }
        .to have_enqueued_job(ChatStreamJob).on_queue("interactive")
    end
  end

  describe "worker configs" do
    it "gives the interactive worker only the interactive queue" do
      queues = sidekiq_config("sidekiq_interactive.yml")[:queues]
      expect(queues).to eq(%w[interactive])
    end

    it "lets the agents worker drain interactive first as overflow" do
      weights = sidekiq_config("sidekiq_agents.yml")[:queues].to_h
      expect(weights.keys).to include("interactive", "agents")
      expect(weights["interactive"]).to be > weights["agents"]
    end
  end
end
