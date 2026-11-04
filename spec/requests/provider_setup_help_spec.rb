# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Provider setup help", type: :request do
  before { sign_in create(:user, :owner) }

  describe "GET /providers/new" do
    before { get new_provider_path }

    it "explains how to use a Claude subscription token" do
      expect(response.body).to include("claude setup-token")
    end

    it "no longer says the token may be restricted" do
      expect(response.body).not_to include("may be restricted")
    end

    it "opens the model server address field for Ollama" do
      expect(response.body).to match(/<details class="mt-4" open>.*Address of your model server/m)
    end
  end

  describe "GET /providers/:id/edit" do
    def edit_body(type)
      provider = create(:provider_config, adapter_type: type, name: "P #{type}")
      get edit_provider_path(provider, edit_mode: true)
      response.body
    end

    it "shows the subscription steps for Anthropic" do
      expect(edit_body("anthropic")).to include("claude setup-token")
    end

    it "omits the subscription steps for OpenAI" do
      expect(edit_body("openai")).not_to include("claude setup-token")
    end

    %w[ollama openai_compatible].each do |type|
      it "opens the model server address field for #{type}" do
        expect(edit_body(type)).to match(/<details class="mt-4" open>.*Address of your model server/m)
      end
    end
  end
end
