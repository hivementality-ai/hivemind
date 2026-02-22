# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::FileSendExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:test_content) { "Hello, world!" }

  describe "#call" do
    context "with valid file path" do
      let(:input) { { "path" => "/workspace/test.txt" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).with("/workspace/test.txt").and_return(true)
        allow(Tools::WorkspaceIo).to receive(:read_file).with("/workspace/test.txt").and_return(test_content)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "reads the file and creates an attachment" do
        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:output]).to include("Sent test.txt")

        attachment = session.chat_attachments.last
        expect(attachment).to be_present
        expect(attachment.filename).to eq("test.txt")
        expect(attachment.content_type).to eq("text/plain")
        expect(attachment.byte_size).to eq(test_content.bytesize)
        expect(attachment.file.attached?).to be true
      end

      it "broadcasts the attachment to the session channel" do
        expect(ActionCable.server).to receive(:broadcast)
          .with("session_#{session.id}", hash_including(
            type: "file_attachment",
            attachment: hash_including(
              filename: "test.txt",
              content_type: "text/plain",
              is_image: false
            )
          ))

        executor.call
      end

      context "with custom filename" do
        let(:input) { { "path" => "/workspace/test.txt", "filename" => "custom.txt" } }

        it "uses the custom filename" do
          result = executor.call

          expect(result.success?).to be true
          attachment = session.chat_attachments.last
          expect(attachment.filename).to eq("custom.txt")
        end
      end
    end

    context "with relative path" do
      let(:input) { { "path" => "test.txt" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).with("/workspace/test.txt").and_return(true)
        allow(Tools::WorkspaceIo).to receive(:read_file).with("/workspace/test.txt").and_return(test_content)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "resolves relative path to workspace" do
        result = executor.call
        expect(result.success?).to be true
      end
    end

    context "with nonexistent file" do
      let(:input) { { "path" => "/workspace/nonexistent.txt" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(false)
      end

      it "returns failure" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("File not found")
      end
    end

    context "with file outside workspace" do
      let(:input) { { "path" => "/etc/passwd" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(false)
      end

      it "returns failure (file not accessible via workspace container)" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("File not found")
      end
    end

    context "with missing path parameter" do
      let(:input) { {} }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("No path provided")
      end
    end

    context "with no session context" do
      let(:input) { { "path" => "/workspace/test.txt" } }
      let(:config) { {} }
      let(:executor) { described_class.new(input: input, config: config, agent: nil) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(true)
        allow(Tools::WorkspaceIo).to receive(:read_file).and_return(test_content)
      end

      it "returns failure" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("No session context")
      end
    end

    context "in team chat context" do
      let(:team_chat_session) { create(:team_chat_session) }
      let(:team_session) { create(:session, agent: agent, team_chat_session: team_chat_session) }
      let(:input) { { "path" => "/workspace/test.txt" } }
      let(:config) { { session: team_session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(true)
        allow(Tools::WorkspaceIo).to receive(:read_file).and_return(test_content)
      end

      it "broadcasts to team chat channel with agent info" do
        expect(ActionCable.server).to receive(:broadcast)
          .with("team_chat_#{team_chat_session.id}", hash_including(
            type: "file_attachment",
            agent_id: agent.id,
            agent_name: agent.name,
            attachment: hash_including(filename: "test.txt")
          ))

        executor.call
      end
    end

    context "when WorkspaceIo raises an error" do
      let(:input) { { "path" => "/workspace/test.txt" } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(true)
        allow(Tools::WorkspaceIo).to receive(:read_file).and_raise(StandardError, "Docker not running")
      end

      it "returns failure with error message" do
        result = executor.call
        expect(result.success?).to be false
        expect(result.error).to include("Failed to send file")
      end
    end
  end
end
