# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ImageGenerateExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:workspace_dir) { Dir.mktmpdir("workspace") }
  let(:generated_dir) { File.join(workspace_dir, "generated", "images") }
  let(:mock_provider) { double("ProviderConfig", adapter_type: "openai", enabled: true) }

  before do
    # Stub WORKSPACE_ROOT to use temp directory
    stub_const("Tools::ImageGenerateExecutor::WORKSPACE_ROOT", workspace_dir)
    stub_const("Tools::ImageGenerateExecutor::GENERATED_DIR", generated_dir)
    
    # Create directory
    FileUtils.mkdir_p(generated_dir)
    
    # Mock provider lookup and API key resolution
    allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(mock_provider)
    allow_any_instance_of(Tools::ImageGenerateExecutor).to receive(:resolve_api_key).and_return("test-api-key")
  end

  after do
    # Clean up temp directory
    FileUtils.rm_rf(workspace_dir) if Dir.exist?(workspace_dir)
  end

  describe "#call" do
    context "with valid prompt" do
      let(:input) { { "prompt" => "A sunset over mountains" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }
      let(:mock_image_url) { "https://example.com/image.png" }
      let(:mock_image_data) { "fake-png-data" }

      before do
        # Mock OpenAI API response
        stub_request(:post, "https://api.openai.com/v1/images/generations")
          .to_return(
            status: 200,
            body: {
              data: [
                { url: mock_image_url }
              ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        # Mock image download
        stub_request(:get, mock_image_url)
          .to_return(
            status: 200,
            body: mock_image_data,
            headers: { "Content-Type" => "image/png" }
          )

        # Mock ActionCable broadcast
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "generates an image and creates an attachment" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:output]).to include("Generated image")
        expect(result.data[:path]).to include("dalle_")
        expect(result.data[:path]).to end_with(".png")
        
        # Check attachment was created
        attachment = session.chat_attachments.last
        expect(attachment).to be_present
        expect(attachment.filename).to start_with("dalle_")
        expect(attachment.filename).to end_with(".png")
        expect(attachment.content_type).to eq("image/png")
        expect(attachment.byte_size).to eq(mock_image_data.bytesize)
        expect(attachment.file.attached?).to be true
      end

      it "saves the image to workspace" do
        result = executor.call

        expect(result.success?).to be true
        
        saved_path = result.data[:path]
        expect(File.exist?(saved_path)).to be true
        expect(File.read(saved_path)).to eq(mock_image_data)
      end

      it "broadcasts the attachment to the session channel" do
        expect(ActionCable.server).to receive(:broadcast)
          .with("session_#{session.id}", hash_including(
            type: "file_attachment",
            attachment: hash_including(
              content_type: "image/png",
              is_image: true
            )
          ))

        executor.call
      end

      context "with custom size" do
        let(:input) { { "prompt" => "A sunset", "size" => "1792x1024" } }

        it "uses the specified size" do
          # Just verify that it accepts the custom size and generates successfully
          result = executor.call

          expect(result.success?).to be true
          expect(result.data[:output]).to include("Generated image")
        end
      end

      context "with invalid size" do
        let(:input) { { "prompt" => "A sunset", "size" => "invalid" } }

        it "returns failure" do
          result = executor.call

          expect(result.success?).to be false
          expect(result.error).to include("Invalid size")
        end
      end
    end

    context "with missing prompt" do
      let(:input) { {} }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("No prompt provided")
      end
    end

    context "when OpenAI provider is not configured" do
      let(:input) { { "prompt" => "A sunset" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(ProviderConfig).to receive(:find_by).and_return(nil)
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("OpenAI provider not configured")
      end
    end

    context "when OpenAI API returns error" do
      let(:input) { { "prompt" => "A sunset" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        stub_request(:post, "https://api.openai.com/v1/images/generations")
          .to_return(
            status: 400,
            body: { error: { message: "Invalid prompt" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("Failed to generate image")
      end
    end

    context "in team chat context" do
      let(:team_chat_session) { create(:team_chat_session) }
      let(:team_session) { create(:session, agent: agent, team_chat_session: team_chat_session) }
      let(:input) { { "prompt" => "A sunset" } }
      let(:config) { { session: team_session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }
      let(:mock_image_url) { "https://example.com/image.png" }
      let(:mock_image_data) { "fake-png-data" }

      before do
        stub_request(:post, "https://api.openai.com/v1/images/generations")
          .to_return(
            status: 200,
            body: { data: [{ url: mock_image_url }] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, mock_image_url)
          .to_return(
            status: 200,
            body: mock_image_data,
            headers: { "Content-Type" => "image/png" }
          )
      end

      it "broadcasts to team chat channel with agent info" do
        expect(ActionCable.server).to receive(:broadcast)
          .with("team_chat_#{team_chat_session.id}", hash_including(
            type: "file_attachment",
            agent_id: agent.id,
            agent_name: agent.name,
            attachment: hash_including(
              content_type: "image/png",
              is_image: true
            )
          ))

        executor.call
      end
    end
  end
end
