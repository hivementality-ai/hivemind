# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Research
  class CancelledError < StandardError; end

  class Loop
    DEPTH_CONFIG = {
      "quick" => { searches: 5, fetches: 8, iterations: 1, doc_pages: 10 },
      "standard" => { searches: 12, fetches: 20, iterations: 2, doc_pages: 30 },
      "deep" => { searches: 25, fetches: 40, iterations: 3, doc_pages: 60 }
    }.freeze

    SOURCE_TRUNCATE = 4000
    SYNTHESIS_TRUNCATE = 5000
    FETCH_TIMEOUT = 15
    MAX_BODY = 50_000

    def initialize(research_session:)
      @rs = research_session
      @config = DEPTH_CONFIG[@rs.depth] || DEPTH_CONFIG["standard"]
      @sources_collected = []
      @findings_collected = []
      @searches_used = 0
      @fetches_used = 0
    end

    def call
      plan = phase_plan
      phase_search(plan)
      analysis = phase_analyze

      remaining_iterations = @config[:iterations] - 1
      remaining_iterations.times do |i|
        break if analysis["sufficient"] == true
        check_cancelled!

        @rs.log_progress("Iteration #{i + 2}: running additional searches...")
        additional = analysis["additional_searches"]
        break if additional.blank?

        phase_iterate(additional)
        analysis = phase_analyze
      end

      phase_synthesize
    end

    private

    # ── Phase 1: PLAN ──

    def phase_plan
      check_cancelled!
      @rs.update!(current_phase: "plan")
      @rs.log_progress("Planning research approach...")

      prompt = build_plan_prompt
      response = llm_call(prompt, max_tokens: 2048, temperature: 0.3)
      plan = parse_json(response)

      plan = default_plan if plan.nil? || plan["search_queries"].blank?

      @rs.log_progress("Plan ready: #{plan['sub_questions']&.size || 0} sub-questions, #{plan['search_queries']&.size || 0} searches")
      plan
    end

    # ── Phase 2: SEARCH ──

    def phase_search(plan)
      check_cancelled!
      @rs.update!(current_phase: "search")
      @rs.log_progress("Searching for information...")

      queries = (plan["search_queries"] || []).first(@config[:searches])

      queries.each_with_index do |query, i|
        check_cancelled!
        break if @searches_used >= @config[:searches]

        @rs.log_progress("Search #{i + 1}/#{queries.size}: #{query.truncate(60)}")
        results = safe_search(query)
        @searches_used += 1

        results.each do |result|
          break if @fetches_used >= @config[:fetches]
          check_cancelled!

          content = safe_fetch(result.url)
          next if content.blank?

          @fetches_used += 1
          source = {
            title: result.title,
            url: result.url,
            snippet: result.snippet,
            content: content.truncate(SOURCE_TRUNCATE)
          }
          @sources_collected << source
          @rs.add_source({ title: result.title, url: result.url, snippet: result.snippet })
        end
      end

      # Process local documents if provided
      if @rs.session.respond_to?(:attachments) && @rs.session.attachments.present?
        process_documents(@rs.session.attachments)
      end

      @rs.log_progress("Search complete: #{@sources_collected.size} sources collected")
    end

    # ── Phase 3: ANALYZE ──

    def phase_analyze
      check_cancelled!
      @rs.update!(current_phase: "analyze")
      @rs.log_progress("Analyzing collected information...")

      prompt = build_analyze_prompt
      response = llm_call(prompt, max_tokens: 4096, temperature: 0.2)
      analysis = parse_json(response)

      if analysis.nil?
        analysis = { "findings" => [ { "topic" => "Analysis", "summary" => response } ], "sufficient" => true }
      end

      (analysis["findings"] || []).each do |finding|
        @findings_collected << finding
        @rs.add_finding(finding)
      end

      @rs.log_progress("Analysis complete: #{@findings_collected.size} findings, gaps: #{analysis['overall_gaps']&.join(', ').to_s.truncate(100)}")
      analysis
    end

    # ── Phase 4: ITERATE ──

    def phase_iterate(additional_searches)
      @rs.update!(current_phase: "iterate")

      queries = (additional_searches || []).first(@config[:searches] - @searches_used)
      return if queries.empty?

      queries.each_with_index do |query, i|
        check_cancelled!
        break if @searches_used >= @config[:searches]

        @rs.log_progress("Additional search #{i + 1}: #{query.truncate(60)}")
        results = safe_search(query)
        @searches_used += 1

        results.each do |result|
          break if @fetches_used >= @config[:fetches]
          check_cancelled!

          content = safe_fetch(result.url)
          next if content.blank?

          @fetches_used += 1
          source = {
            title: result.title,
            url: result.url,
            snippet: result.snippet,
            content: content.truncate(SOURCE_TRUNCATE)
          }
          @sources_collected << source
          @rs.add_source({ title: result.title, url: result.url, snippet: result.snippet })
        end
      end
    end

    # ── Phase 5: SYNTHESIZE ──

    def phase_synthesize
      check_cancelled!
      @rs.update!(current_phase: "synthesize")
      @rs.log_progress("Synthesizing final report...")

      prompt = build_synthesize_prompt
      report = llm_call(prompt, max_tokens: 8192, temperature: 0.3)

      @rs.complete!(report)
      @rs.log_progress("Research complete!")

      inject_into_session(report)
    end

    # ── LLM Calls ──

    def llm_call(messages, max_tokens: 4096, temperature: 0.3)
      agent = @rs.agent
      resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent: agent)
      raise "LLM provider resolution failed: #{resolver.error}" unless resolver.success?

      adapter = resolver.data[:adapter]
      options = { model: agent.llm_model, max_tokens: max_tokens, temperature: temperature }

      result = adapter.chat(messages: messages, options: options)
      raise "LLM call failed: #{result.error}" unless result.success?

      result.data[:content].to_s
    end

    # ── Search & Fetch ──

    def safe_search(query)
      Search::Resolver.provider.search(query, count: 5)
    rescue StandardError => e
      @rs.log_progress("Search failed for '#{query.truncate(40)}': #{e.message.truncate(80)}")
      []
    end

    def safe_fetch(url)
      uri = URI.parse(url)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = FETCH_TIMEOUT
      http.read_timeout = FETCH_TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Hivemind/1.0"
      request["Accept"] = "text/html, text/plain, application/json"

      response = http.request(request)
      return nil unless response.code.to_i < 400

      body = response.body.to_s
                .force_encoding("UTF-8")
                .encode("UTF-8", invalid: :replace, undef: :replace, replace: "\uFFFD")
                .truncate(MAX_BODY)

      if response["content-type"]&.include?("html")
        body = body.gsub(/<script[^>]*>.*?<\/script>/mi, "")
                   .gsub(/<style[^>]*>.*?<\/style>/mi, "")
                   .gsub(/<[^>]+>/, " ")
                   .gsub(/\s+/, " ")
                   .strip
      end

      body.presence
    rescue StandardError => e
      @rs.log_progress("Fetch failed for #{url.truncate(60)}: #{e.message.truncate(80)}")
      nil
    end

    def process_documents(documents)
      documents.first(@config[:doc_pages]).each do |doc|
        check_cancelled!
        next unless doc.respond_to?(:path) && doc.path&.end_with?(".pdf")

        begin
          script_path = Rails.root.join("lib/scripts/pdf_extract.py").to_s
          stdout, _stderr, status = Open3.capture3("python3", script_path, doc.path)
          next unless status.success?

          source = {
            title: File.basename(doc.path),
            url: "local://#{doc.path}",
            snippet: "Local document",
            content: stdout.truncate(SOURCE_TRUNCATE)
          }
          @sources_collected << source
          @rs.add_source({ title: source[:title], url: source[:url], snippet: source[:snippet] })
        rescue StandardError => e
          @rs.log_progress("Document processing failed: #{e.message.truncate(80)}")
        end
      end
    end

    # ── Prompt Builders ──

    def build_plan_prompt
      [
        { role: "system", content: <<~SYS },
          You are a research planning assistant. Given a research query, decompose it into sub-questions and search queries.
          Respond ONLY with valid JSON:
          {
            "sub_questions": ["question 1", "question 2", ...],
            "search_queries": ["search query 1", "search query 2", ...],
            "key_entities": ["entity 1", "entity 2", ...]
          }
        SYS
        { role: "user", content: "Research query: #{@rs.query}\nFocus area: #{@rs.focus}\nDepth: #{@rs.depth}" }
      ]
    end

    def build_analyze_prompt
      source_text = @sources_collected.map { |s|
        "### #{s[:title]}\nURL: #{s[:url]}\n#{s[:content].to_s.truncate(SOURCE_TRUNCATE)}\n"
      }.join("\n---\n")

      [
        { role: "system", content: <<~SYS },
          You are a research analyst. Analyze the collected sources and extract findings.
          Respond ONLY with valid JSON:
          {
            "findings": [
              {"topic": "topic name", "summary": "key finding", "confidence": "high/medium/low", "sources": ["url1"]}
            ],
            "overall_gaps": ["gap 1", "gap 2"],
            "additional_searches": ["query to fill gap 1", "query to fill gap 2"],
            "sufficient": true/false
          }
        SYS
        { role: "user", content: "Research query: #{@rs.query}\nFocus: #{@rs.focus}\n\nCollected sources:\n#{source_text}" }
      ]
    end

    def build_synthesize_prompt
      findings_text = @findings_collected.map { |f|
        "- #{f['topic'] || f[:topic]}: #{(f['summary'] || f[:summary]).to_s.truncate(SYNTHESIS_TRUNCATE)}"
      }.join("\n")

      source_text = @sources_collected.map { |s|
        "### #{s[:title]}\nURL: #{s[:url]}\n#{s[:content].to_s.truncate(SYNTHESIS_TRUNCATE)}\n"
      }.join("\n---\n")

      format_instruction = case @rs.output_format
      when "bullet_points"
        "Format as a structured list of bullet points with headers."
      when "detailed_analysis"
        "Write a detailed, long-form analysis with sections, evidence, and citations."
      when "executive_summary"
        "Write a concise executive summary with key takeaways and recommendations."
      else
        "Write a comprehensive research report with introduction, sections, and conclusion."
      end

      [
        { role: "system", content: <<~SYS },
          You are a research report writer. Synthesize the findings and sources into a final report.
          #{format_instruction}
          Include citations to sources where relevant using [Source Title](URL) format.
          Be thorough, accurate, and well-organized.
        SYS
        { role: "user", content: "Research query: #{@rs.query}\n\nKey findings:\n#{findings_text}\n\nSource material:\n#{source_text}" }
      ]
    end

    # ── Helpers ──

    def check_cancelled!
      raise Research::CancelledError, "Research cancelled" if @rs.cancelled?
    end

    def default_plan
      {
        "sub_questions" => [ @rs.query ],
        "search_queries" => [ @rs.query, "#{@rs.query} overview", "#{@rs.query} latest research" ],
        "key_entities" => []
      }
    end

    def parse_json(text)
      return nil if text.blank?

      # Strip markdown code fences
      cleaned = text.gsub(/```json\s*/i, "").gsub(/```\s*/, "")

      # Try direct parse
      JSON.parse(cleaned)
    rescue JSON::ParserError
      # Try extracting JSON object
      match = text.match(/\{.*\}/m)
      return nil unless match

      begin
        JSON.parse(match[0])
      rescue JSON::ParserError
        nil
      end
    end

    def inject_into_session(report)
      callback_message = <<~MSG.strip
        [Deep Research Complete] #{@rs.query.truncate(100)}

        #{report.truncate(3000)}

        (Task ID: #{@rs.task_key} | #{@rs.sources_count} sources analyzed | Use deep_research_status for full report)
      MSG

      ChatStreamJob.perform_later(
        @rs.session.id,
        callback_message,
        []
      )
    end
  end
end
