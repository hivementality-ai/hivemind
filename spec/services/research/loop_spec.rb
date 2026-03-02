# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::Loop do
  subject { described_class.new(research_session: research_session) }

  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent) }
  let(:research_session) do
    create(:research_session, :running,
      agent: agent,
      session: session,
      query: "What are the latest advances in quantum computing?",
      depth: "quick"
    )
  end

  let(:mock_adapter) { instance_double("Adapter") }
  let(:mock_search_provider) { instance_double("Search::Duckduckgo") }

  let(:plan_response) do
    {
      "sub_questions" => [ "What is quantum computing?", "What are recent breakthroughs?" ],
      "search_queries" => [ "quantum computing advances 2026", "quantum computing breakthroughs" ],
      "key_entities" => [ "IBM", "Google" ]
    }.to_json
  end

  let(:analyze_response) do
    {
      "findings" => [
        { "topic" => "Quantum Computing", "summary" => "Major advances in error correction", "confidence" => "high", "sources" => [ "https://example.com" ] }
      ],
      "overall_gaps" => [],
      "additional_searches" => [],
      "sufficient" => true
    }.to_json
  end

  let(:synthesize_response) { "# Quantum Computing Report\n\nQuantum computing has seen major advances." }

  let(:search_results) do
    [
      OpenStruct.new(title: "Quantum Advances", url: "https://example.com/quantum", snippet: "Recent quantum computing advances"),
      OpenStruct.new(title: "Quantum News", url: "https://example.com/news", snippet: "Latest news on quantum computing")
    ]
  end

  before do
    # Mock LLM provider
    resolver_response = ServiceResponse.success(data: { adapter: mock_adapter })
    allow(Providers::Resolver).to receive(:call).and_return(resolver_response)

    # Mock LLM calls in sequence: plan, analyze, synthesize
    allow(mock_adapter).to receive(:chat).and_return(
      ServiceResponse.success(data: { content: plan_response }),
      ServiceResponse.success(data: { content: analyze_response }),
      ServiceResponse.success(data: { content: synthesize_response })
    )

    # Mock search provider
    allow(Search::Resolver).to receive(:provider).and_return(mock_search_provider)
    allow(mock_search_provider).to receive(:search).and_return(search_results)

    # Mock web fetch
    stub_request(:get, /example\.com/).to_return(
      status: 200,
      body: "<html><body>Quantum computing content here</body></html>",
      headers: { "content-type" => "text/html" }
    )

    # Mock ActionCable
    allow(ActionCable.server).to receive(:broadcast)

    # Mock ChatStreamJob
    allow(ChatStreamJob).to receive(:perform_later)
  end

  describe "#call" do
    it "runs all five phases" do
      subject.call

      research_session.reload
      expect(research_session.status).to eq("completed")
      expect(research_session.report).to be_present
      expect(research_session.completed_at).to be_present
    end

    it "collects sources from search" do
      subject.call

      research_session.reload
      expect(research_session.sources_count).to be > 0
    end

    it "collects findings from analysis" do
      subject.call

      research_session.reload
      expect(research_session.findings.size).to be > 0
    end

    it "logs progress throughout" do
      subject.call

      research_session.reload
      expect(research_session.progress_log.size).to be > 0
      messages = research_session.progress_log.map { |e| e["message"] }
      expect(messages).to include(a_string_matching(/Planning/))
      expect(messages).to include(a_string_matching(/Searching/))
      expect(messages).to include(a_string_matching(/Analyzing/))
      expect(messages).to include(a_string_matching(/Synthesizing/))
    end

    it "injects result into parent session" do
      subject.call

      expect(ChatStreamJob).to have_received(:perform_later).with(
        session.id,
        a_string_matching(/Deep Research Complete/),
        []
      )
    end

    it "calls LLM adapter three times for quick depth" do
      subject.call

      expect(mock_adapter).to have_received(:chat).exactly(3).times
    end
  end

  describe "cancellation" do
    it "raises CancelledError when cancelled" do
      # Cancel after plan phase
      call_count = 0
      allow(research_session).to receive(:cancelled?) do
        call_count += 1
        call_count > 2 # Cancel after second check
      end

      expect { subject.call }.to raise_error(Research::CancelledError)
    end
  end

  describe "iteration logic" do
    let(:research_session) do
      create(:research_session, :running,
        agent: agent,
        session: session,
        query: "What are the latest advances in quantum computing?",
        depth: "standard" # standard allows 2 iterations
      )
    end

    let(:insufficient_analysis) do
      {
        "findings" => [
          { "topic" => "Quantum Computing", "summary" => "Initial finding", "confidence" => "medium" }
        ],
        "overall_gaps" => [ "Need more on error correction" ],
        "additional_searches" => [ "quantum error correction 2026" ],
        "sufficient" => false
      }.to_json
    end

    it "runs additional iterations when analysis is insufficient" do
      allow(mock_adapter).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: plan_response }),
        ServiceResponse.success(data: { content: insufficient_analysis }),
        ServiceResponse.success(data: { content: analyze_response }), # second analysis says sufficient
        ServiceResponse.success(data: { content: synthesize_response })
      )

      subject.call

      research_session.reload
      expect(research_session.status).to eq("completed")
      # Should have called chat 4 times: plan + analyze + re-analyze + synthesize
      expect(mock_adapter).to have_received(:chat).exactly(4).times
    end
  end

  describe "error resilience" do
    it "continues when a search fails" do
      allow(mock_search_provider).to receive(:search).and_raise(StandardError.new("Search API down"))

      # Should still complete (with empty sources)
      subject.call

      research_session.reload
      expect(research_session.status).to eq("completed")
    end

    it "continues when a fetch fails" do
      stub_request(:get, /example\.com/).to_timeout

      subject.call

      research_session.reload
      expect(research_session.status).to eq("completed")
    end
  end

  describe "JSON parsing" do
    it "handles JSON wrapped in code fences" do
      fenced = "```json\n#{plan_response}\n```"
      allow(mock_adapter).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: fenced }),
        ServiceResponse.success(data: { content: analyze_response }),
        ServiceResponse.success(data: { content: synthesize_response })
      )

      subject.call
      research_session.reload
      expect(research_session.status).to eq("completed")
    end

    it "falls back to defaults on invalid JSON" do
      allow(mock_adapter).to receive(:chat).and_return(
        ServiceResponse.success(data: { content: "Not valid JSON at all" }),
        ServiceResponse.success(data: { content: analyze_response }),
        ServiceResponse.success(data: { content: synthesize_response })
      )

      subject.call
      research_session.reload
      expect(research_session.status).to eq("completed")
    end
  end

  describe "LLM failure" do
    it "raises when LLM provider resolution fails" do
      allow(Providers::Resolver).to receive(:call).and_return(
        ServiceResponse.failure(error: "No API key configured")
      )

      expect { subject.call }.to raise_error(RuntimeError, /LLM provider resolution failed/)
    end

    it "raises when LLM chat call fails" do
      allow(mock_adapter).to receive(:chat).and_return(
        ServiceResponse.failure(error: "Rate limited")
      )

      expect { subject.call }.to raise_error(RuntimeError, /LLM call failed/)
    end
  end
end
