# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::CanvasExecutor do
  let(:session) { create(:session) }
  let(:agent) { session.agent }
  let(:config) { { session: session } }

  def execute(input)
    described_class.new(input: input, config: config, agent: agent).call
  end

  describe "#call" do
    context "with unknown action" do
      it "returns failure" do
        result = execute("action" => "explode")
        expect(result.success?).to be(false)
        expect(result.error).to include("Unknown canvas action")
      end
    end

    context "with missing action" do
      it "returns failure" do
        result = execute({})
        expect(result.success?).to be(false)
        expect(result.error).to include("Unknown canvas action")
      end
    end

    context "without session" do
      let(:config) { {} }

      it "returns failure" do
        result = execute("action" => "render", "html" => "<p>hi</p>")
        expect(result.success?).to be(false)
        expect(result.error).to include("No session context")
      end
    end

    context "render action" do
      it "broadcasts and returns success" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "canvas_#{session.id}",
          hash_including(type: "render", html: "<h1>Hello</h1>")
        )

        result = execute("action" => "render", "html" => "<h1>Hello</h1>", "title" => "Test")
        expect(result.success?).to be(true)
        expect(result.data[:output]).to include("Canvas rendered")
        expect(result.data[:output]).to include("Test")
      end

      it "defaults title to Canvas" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "canvas_#{session.id}",
          hash_including(title: "Canvas")
        )

        execute("action" => "render", "html" => "<p>x</p>")
      end

      it "requires html" do
        result = execute("action" => "render", "html" => "")
        expect(result.success?).to be(false)
        expect(result.error).to include("html parameter is required")
      end
    end

    context "update action" do
      it "broadcasts element update" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "canvas_#{session.id}",
          hash_including(type: "update", element_id: "chart1", html: "<p>new</p>")
        )

        result = execute("action" => "update", "element_id" => "chart1", "html" => "<p>new</p>")
        expect(result.success?).to be(true)
      end

      it "requires element_id" do
        result = execute("action" => "update", "html" => "<p>x</p>")
        expect(result.success?).to be(false)
        expect(result.error).to include("element_id is required")
      end
    end

    context "append action" do
      it "broadcasts append" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "canvas_#{session.id}",
          hash_including(type: "append", html: "<p>more</p>")
        )

        result = execute("action" => "append", "html" => "<p>more</p>")
        expect(result.success?).to be(true)
      end
    end

    context "clear action" do
      it "broadcasts clear" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "canvas_#{session.id}",
          hash_including(type: "clear")
        )

        result = execute("action" => "clear")
        expect(result.success?).to be(true)
        expect(result.data[:output]).to include("Canvas cleared")
      end
    end
  end
end
