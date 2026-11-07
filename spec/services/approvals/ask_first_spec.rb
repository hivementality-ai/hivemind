# frozen_string_literal: true

require "rails_helper"

RSpec.describe Approvals::AskFirst do
  def category(type, input)
    described_class.category(executor_type: type, input: input)
  end

  describe ".category" do
    it "asks before Gmail send and reply" do
      expect(category("google_gmail", { "action" => "send" })).to eq("send_email")
      expect(category("google_gmail", { "action" => "reply" })).to eq("send_email")
    end

    it "asks before SMTP email send" do
      expect(category("email", { "action" => "send" })).to eq("send_email")
      expect(category("email", { "action" => "send_html" })).to eq("send_email")
    end

    it "asks before posting a message to a channel" do
      expect(category("message", { "action" => "send" })).to eq("post_message")
      expect(category("message", { "channel" => "slack" })).to eq("post_message")
    end

    it "asks before deleting a file" do
      expect(category("cloud_storage", { "action" => "delete" })).to eq("delete_file")
    end

    it "asks before an HTTP request that is not a GET" do
      %w[POST PUT PATCH DELETE post].each do |verb|
        expect(category("http_request", { "method" => verb })).to eq("external_write")
      end
    end

    it "never asks before reads" do
      expect(category("google_gmail", { "action" => "list" })).to be_nil
      expect(category("google_gmail", { "action" => "draft" })).to be_nil
      expect(category("email", { "action" => "config" })).to be_nil
      expect(category("message", { "action" => "list_channels" })).to be_nil
      expect(category("cloud_storage", { "action" => "read" })).to be_nil
      expect(category("http_request", { "method" => "GET" })).to be_nil
      expect(category("http_request", { "url" => "https://x.test" })).to be_nil
      expect(category("http_request", { "action" => "list_apis" })).to be_nil
      expect(category("file_read", { "path" => "a" })).to be_nil
    end

    it "accepts symbol keys" do
      expect(category("email", { action: "send" })).to eq("send_email")
    end
  end

  describe ".category_to_ask" do
    let(:agent) { create(:agent) }

    it "asks by default" do
      expect(described_class.category_to_ask(agent: agent, executor_type: "email", input: { "action" => "send" })).to eq("send_email")
    end

    it "does not ask once the agent turned that category off" do
      agent.update!(ask_first: { "send_email" => "0" })

      expect(described_class.category_to_ask(agent: agent, executor_type: "email", input: { "action" => "send" })).to be_nil
      expect(described_class.category_to_ask(agent: agent, executor_type: "message", input: {})).to eq("post_message")
    end
  end
end
