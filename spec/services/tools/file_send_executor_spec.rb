# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::FileSendExecutor do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:workspace_dir) { Dir.mktmpdir("workspace") }
  let(:test_file_path) { File.join(workspace_dir, "test.txt") }
  let(:test_content) { "Hello, world!" }

  before do
    # Stub WORKSPACE_ROOT to use temp directory
    stub_const("Tools::FileSendExecutor::WORKSPACE_ROOT", workspace_dir)

    # Create test file
    File.write(test_file_path, test_content)
  end

  after do
    # Clean up temp directory
    FileUtils.rm_rf(workspace_dir) if Dir.exist?(workspace_dir)
  end

  describe "#call" do
    context "with valid file path" do
      let(:input) { { "path" => test_file_path } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      it "reads the file and creates an attachment" do
        # Mock ActionCable broadcast
        allow(ActionCable.server).to receive(:broadcast)

        result = executor.call

        expect(result.success?).to be true
        expect(result.data[:output]).to include("Sent test.txt")

        # Check attachment was created
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
        let(:input) { { "path" => test_file_path, "filename" => "custom.txt" } }

        it "uses the custom filename" do
          allow(ActionCable.server).to receive(:broadcast)

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

      it "resolves relative path to workspace" do
        allow(ActionCable.server).to receive(:broadcast)

        result = executor.call

        expect(result.success?).to be true
      end
    end

    context "with path outside workspace" do
      let(:outside_path) { File.join(Dir.tmpdir, "outside.txt") }
      let(:input) { { "path" => outside_path } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        File.write(outside_path, "outside")
      end

      after do
        FileUtils.rm_f(outside_path) if File.exist?(outside_path)
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("Access denied")
      end
    end

    context "with nonexistent file" do
      let(:input) { { "path" => File.join(workspace_dir, "nonexistent.txt") } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("File not found")
      end
    end

    context "with directory path" do
      let(:dir_path) { File.join(workspace_dir, "testdir") }
      let(:input) { { "path" => dir_path } }
      let(:config) { { session: session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

      before do
        FileUtils.mkdir_p(dir_path)
      end

      after do
        FileUtils.rm_rf(dir_path) if Dir.exist?(dir_path)
      end

      it "returns failure" do
        result = executor.call

        expect(result.success?).to be false
        expect(result.error).to include("Cannot send directory")
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

    context "in team chat context" do
      let(:team_chat_session) { create(:team_chat_session) }
      let(:team_session) { create(:session, agent: agent, team_chat_session: team_chat_session) }
      let(:input) { { "path" => test_file_path } }
      let(:config) { { session: team_session } }
      let(:executor) { described_class.new(input: input, config: config, agent: agent) }

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
  end
end
