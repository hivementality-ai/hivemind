# frozen_string_literal: true

require "rails_helper"

# A memory the user forgot (archived) must never reach the agent or the UI again.
RSpec.describe "Forgotten memories stay forgotten" do
  let(:agent) { create(:agent) }

  def entry(content, **attrs)
    create(:memory_entry, agent: agent, content: content, importance: 0.9, **attrs)
  end

  def forgotten(content, **attrs)
    entry(content, **attrs).tap(&:forget!)
  end

  describe Memory::ContextBuilder do
    before { allow(Memory::Embedding).to receive(:generate_query).and_return(nil) }

    it "does not inject a forgotten preference" do
      entry("Likes tea", memory_type: "preference")
      forgotten("Likes coffee", memory_type: "preference")

      context = described_class.call(agent: agent, query: "hello there")[:context]

      expect(context).to include("Likes tea")
      expect(context).not_to include("Likes coffee")
    end

    it "does not inject a forgotten recent fact" do
      entry("Works at Acme", memory_type: "semantic")
      forgotten("Works at Initech", memory_type: "semantic")

      context = described_class.call(agent: agent, query: "hello there")[:context]

      expect(context).to include("Works at Acme")
      expect(context).not_to include("Initech")
    end

    it "does not return a forgotten memory from the keyword fallback" do
      entry("Cat is called Miso", memory_type: "semantic")
      forgotten("Cat is called Felix", memory_type: "semantic")

      builder = described_class.new(agent: agent, query: "what is my cat called")
      contents = builder.send(:keyword_fallback).map(&:content)

      expect(contents).to eq([ "Cat is called Miso" ])
    end
  end

  describe Memory::FileSync do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it "leaves forgotten memories out of the raw MEMORY.md" do
      entry("Likes tea", memory_type: "preference")
      entry("Works at Acme", memory_type: "semantic")
      entry("Deploy with make ship", memory_type: "procedural")
      forgotten("Likes coffee", memory_type: "preference")
      forgotten("Works at Initech", memory_type: "semantic")
      forgotten("Deploy with make doom", memory_type: "procedural")
      file = File.join(dir, "MEMORY.md")

      described_class.new(agent: agent).send(:write_raw_memory, file)
      text = File.read(file)

      expect(text).to include("Likes tea", "Works at Acme", "make ship")
      expect(text).not_to include("coffee", "Initech", "make doom")
    end

    it "leaves forgotten memories out of recent_context.md" do
      entry("Works at Acme", memory_type: "semantic")
      forgotten("Works at Initech", memory_type: "semantic")

      described_class.new(agent: agent).send(:write_recent_context, dir)
      text = File.read(File.join(dir, "recent_context.md"))

      expect(text).to include("Acme")
      expect(text).not_to include("Initech")
    end
  end

  describe Memory::Summarizer do
    it "does not feed forgotten memories to the summarizer" do
      entry("Remember tea", memory_type: "semantic", metadata: { "source" => "hashtag_action" })
      forgotten("Remember doom", memory_type: "semantic", metadata: { "source" => "hashtag_action" })
      entry("Likes green", memory_type: "preference")
      forgotten("Likes red", memory_type: "preference")
      entry("Fact alive", memory_type: "semantic")
      forgotten("Fact dead", memory_type: "semantic")
      entry("Proc alive", memory_type: "procedural")
      forgotten("Proc dead", memory_type: "procedural")

      raw = described_class.new(agent: agent).send(:build_raw_content)

      expect(raw).to include("Remember tea", "Likes green", "Fact alive", "Proc alive")
      expect(raw).not_to include("doom", "Likes red", "Fact dead", "Proc dead")
    end
  end

  describe "hashtag actions" do
    let(:session) { create(:session, agent: agent) }

    it "#search skips forgotten memories" do
      entry("banana bread recipe")
      forgotten("banana smoothie recipe")

      response = HashtagActions::Actions::Search.call(agent: agent, session: session, payload: "banana")[:response]

      expect(response).to include("bread")
      expect(response).not_to include("smoothie")
    end

    it "#forget only matches active memories" do
      live = entry("banana bread recipe")
      gone = forgotten("banana smoothie recipe")
      allow(Memory::FileSync).to receive(:call)

      HashtagActions::Actions::Forget.call(agent: agent, session: session, payload: "banana")

      expect(MemoryEntry.exists?(live.id)).to be(false)
      expect(MemoryEntry.exists?(gone.id)).to be(true)
    end
  end

  describe MemoryEntry do
    it "find_duplicate ignores a forgotten near-duplicate" do
      vector = Array.new(768, 0.1)
      forgotten("Lives in Berlin", embedding: vector)

      expect(described_class.find_duplicate(embedding: vector, agent: agent)).to be_nil
    end

    it "find_duplicate still finds an active near-duplicate" do
      vector = Array.new(768, 0.1)
      live = entry("Lives in Berlin", embedding: vector)

      expect(described_class.find_duplicate(embedding: vector, agent: agent)).to eq(live)
    end

    it "relevance_search ignores forgotten memories by default" do
      vector = Array.new(768, 0.1)
      live = entry("Lives in Berlin", embedding: vector)
      forgotten("Lives in Paris", embedding: vector)

      expect(described_class.relevance_search(embedding: vector, agent: agent)).to eq([ live ])
    end
  end

  describe "pages", type: :request do
    let(:owner) { create(:user, :owner) }

    before { sign_in owner }

    it "agent page lists and counts only live memories" do
      entry("Visible memory", memory_type: "semantic")
      forgotten("Hidden memory", memory_type: "semantic")
      entry("Chat log line", memory_type: "episodic")

      get agent_path(agent)

      expect(response.body).to include("Visible memory")
      expect(response.body).not_to include("Hidden memory")
      expect(response.body).not_to include("Chat log line")
      expect(response.body).to include("Memories (1)")
    end

    it "heartbeat page ignores a forgotten system memory" do
      soul = Agent.system_assistant
      create(:memory_entry, agent: soul, content: "Live heartbeat note", updated_at: 2.days.ago)
      create(:memory_entry, agent: soul, content: "Forgotten heartbeat note").forget!

      get heartbeats_path

      expect(response.body).to include("Live heartbeat note")
      expect(response.body).not_to include("Forgotten heartbeat note")
    end
  end
end
