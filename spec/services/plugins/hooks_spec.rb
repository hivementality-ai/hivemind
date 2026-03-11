# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plugins::Hooks do
  before { described_class.reset! }

  describe ".register" do
    it "registers a handler for a valid event" do
      handler = Class.new { def call(_payload); end }
      described_class.register("before_chat", handler)

      expect(described_class.registered_for("before_chat")).to include(handler)
    end

    it "raises for unknown event" do
      handler = Class.new
      expect {
        described_class.register("unknown_event", handler)
      }.to raise_error(ArgumentError, /Unknown hook event/)
    end

    it "accepts string class names" do
      stub_const("TestHookHandler", Class.new { def call(_payload); end })
      described_class.register("before_chat", "TestHookHandler")

      expect(described_class.registered_for("before_chat")).to include(TestHookHandler)
    end

    it "deduplicates handlers" do
      handler = Class.new { def call(_payload); end }
      described_class.register("before_chat", handler)
      described_class.register("before_chat", handler)

      expect(described_class.registered_for("before_chat").size).to eq(1)
    end

    it "accepts symbol event names" do
      handler = Class.new { def call(_payload); end }
      described_class.register(:before_chat, handler)

      expect(described_class.registered_for(:before_chat)).to include(handler)
    end
  end

  describe ".unregister" do
    it "removes a registered handler" do
      handler = Class.new { def call(_payload); end }
      described_class.register("before_chat", handler)
      described_class.unregister("before_chat", handler)

      expect(described_class.registered_for("before_chat")).to be_empty
    end
  end

  describe ".trigger" do
    it "calls all handlers for the event" do
      handler_a = Class.new do
        def call(payload)
          ServiceResponse.success(data: { handler: "a", received: payload })
        end
      end
      handler_b = Class.new do
        def call(payload)
          ServiceResponse.success(data: { handler: "b", received: payload })
        end
      end

      described_class.register("after_chat", handler_a)
      described_class.register("after_chat", handler_b)

      result = described_class.trigger("after_chat", { message: "hello" })
      expect(result).to be_success
      expect(result.data[:results].size).to eq(2)
    end

    it "catches handler errors and continues" do
      failing_handler = Class.new do
        def call(_payload)
          raise "boom"
        end
      end
      success_handler = Class.new do
        def call(_payload)
          ServiceResponse.success(data: { ok: true })
        end
      end

      described_class.register("before_tool_call", failing_handler)
      described_class.register("before_tool_call", success_handler)

      result = described_class.trigger("before_tool_call")
      expect(result).to be_success
      expect(result.data[:results].size).to eq(2)
      expect(result.data[:results].first.error).to include("boom")
      expect(result.data[:results].last).to be_success
    end

    it "returns empty results for events with no handlers" do
      result = described_class.trigger("session_created")
      expect(result).to be_success
      expect(result.data[:results]).to be_empty
    end
  end

  describe ".registered_for" do
    it "returns empty array for unregistered events" do
      expect(described_class.registered_for("agent_created")).to eq([])
    end
  end

  describe ".reset!" do
    it "clears all handlers" do
      handler = Class.new { def call(_payload); end }
      described_class.register("before_chat", handler)
      described_class.reset!

      expect(described_class.registered_for("before_chat")).to be_empty
    end
  end

  describe "VALID_EVENTS" do
    it "contains expected events" do
      expect(Plugins::Hooks::VALID_EVENTS).to include(
        "before_chat", "after_chat",
        "before_tool_call", "after_tool_call",
        "agent_created", "session_created"
      )
    end
  end
end
