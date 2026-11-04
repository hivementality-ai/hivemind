# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integrations and channels settings pass", type: :request do
  before { sign_in create(:user) }

  describe "Cloud Storage card" do
    it "puts the remote forms behind an Advanced details wrapper" do
      get integrations_path

      expect(response.body).to match(%r{<details[^>]*>\s*<summary[^>]*>Advanced</summary>.*Add Remote.*</details>}m)
    end

    it "no longer mentions rclone in the subtitle" do
      get integrations_path

      expect(response.body).not_to include("SFTP via rclone")
    end

    it "warns that the Google Drive token step needs a terminal" do
      get integrations_path

      expect(response.body).to include("needs a terminal")
    end
  end

  describe "test connection buttons" do
    before do
      VaultEntry.create!(namespace: "github", key: "token", value: "x")
      VaultEntry.create!(namespace: "trello", key: "api_key", value: "x")
      VaultEntry.create!(namespace: "search", key: "provider", value: "brave")
      VaultEntry.create!(namespace: "search", key: "api_key", value: "x")
    end

    it "leaves no alert( call in the page" do
      get integrations_path

      expect(response.body).not_to include("alert(")
    end

    it "wires each test button to the connection-test controller with a status slot" do
      get integrations_path

      expect(response.body.scan('data-controller="connection-test"').size).to eq(3)
      expect(response.body.scan('data-connection-test-target="status"').size).to eq(3)
      expect(response.body).not_to include('onclick="test')
    end
  end

  describe "platform lists" do
    it "lists every platform on the channel form, the channels page and the integrations card" do
      get new_channel_path
      form = response.body
      get channels_path
      index = response.body
      get integrations_path
      integrations = response.body

      Channel::PLATFORMS.each do |label, type|
        expect(form).to include(%(value="#{type}"))
        expect(form).to include(ERB::Util.html_escape(label))
        expect(index).to include(ERB::Util.html_escape(label))
        expect(integrations).to include(ERB::Util.html_escape(label))
      end
    end
  end
end
