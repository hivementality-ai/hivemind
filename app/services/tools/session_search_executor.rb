# frozen_string_literal: true

module Tools
  # Full-text search across session history using PostgreSQL FTS.
  #
  # Privacy scoping: agents only see their own sessions by default.
  # System agents (system_agent: true) can search across all sessions.
  #
  # Parameters:
  #   query        - required - keywords to search for
  #   limit        - optional - max results (1-20, default 10)
  #   agent_filter - optional - agent name or slug to restrict results to
  #   from         - optional - ISO8601 date string, lower bound on updated_at
  #   to           - optional - ISO8601 date string, upper bound on updated_at
  class SessionSearchExecutor < BaseExecutor
    MAX_RESULTS   = 20
    SNIPPET_LEN   = 300
    HIGHLIGHT_PRE = "**"
    HIGHLIGHT_SUF = "**"

    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "No query provided") if query.empty?

      limit        = (input["limit"] || 10).to_i.clamp(1, MAX_RESULTS)
      agent_filter = input["agent_filter"].to_s.strip.presence
      from         = parse_date(input["from"])
      to           = parse_date(input["to"])

      scope = build_scope(query:, agent_filter:, from:, to:)
      results = scope.limit(limit)

      if results.any?
        output = format_results(results, query)
        ServiceResponse.success(data: { output: output, exit_code: 0 })
      else
        ServiceResponse.success(data: {
          output: "No sessions found matching '#{query}'#{filter_note(agent_filter, from, to)}.",
          exit_code: 0
        })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Session search failed: #{e.message}")
    end

    private

    # Returns the base scope with privacy scoping, FTS filter, date range,
    # and agent filter applied, ordered by relevance then recency.
    def build_scope(query:, agent_filter:, from:, to:)
      tsquery  = sanitized_tsquery(query)
      rank_sql = "ts_rank_cd(sessions.fts_vector, to_tsquery('english', #{ActiveRecord::Base.connection.quote(tsquery)}), 32)"

      scope = Session.includes(:agent)
                     .where("sessions.fts_vector @@ to_tsquery('english', ?)", tsquery)

      scope = apply_privacy(scope)
      scope = apply_agent_filter(scope, agent_filter) if agent_filter
      scope = scope.where("sessions.updated_at >= ?", from) if from
      scope = scope.where("sessions.updated_at <= ?", to)   if to

      scope.order(Arel.sql("#{rank_sql} DESC, sessions.updated_at DESC"))
    end

    # Agents only see their own sessions unless they are a system agent.
    def apply_privacy(scope)
      return scope if agent.nil? || agent.system_agent?

      scope.where(agent_id: agent.id)
    end

    # Filter by agent name or slug (case-insensitive)
    def apply_agent_filter(scope, agent_filter)
      target = Agent.where(
        "LOWER(name) = :v OR LOWER(slug) = :v",
        v: agent_filter.downcase
      ).first

      return scope.none unless target

      # Non-system agents can only filter down to themselves
      if agent && !agent.system_agent? && target.id != agent.id
        return scope.none
      end

      scope.where(agent_id: target.id)
    end

    def format_results(results, query)
      lines = ["Found #{results.size} session(s) matching '#{query}':\n"]

      results.each_with_index do |session, idx|
        agent_name  = session.agent&.name || "—"
        updated     = session.updated_at.strftime("%Y-%m-%d %H:%M")
        msg_count   = (session.transcript || []).size
        snippet     = extract_snippet(session, query)

        lines << "#{idx + 1}. [#{session.session_key}] #{session.title || "Untitled"}"
        lines << "   Agent: #{agent_name} | Updated: #{updated} | Messages: #{msg_count}"
        lines << "   #{snippet}" if snippet.present?
        lines << ""
      end

      lines.join("\n")
    end

    # Pull the most relevant message snippet from the transcript and
    # highlight matching keywords.
    def extract_snippet(session, query)
      messages = Array(session.transcript)
      return nil if messages.empty?

      keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }
      return nil if keywords.empty?

      # Find the message whose content contains the most keyword hits
      best = messages.max_by do |msg|
        content = (msg["content"] || msg[:content]).to_s.downcase
        keywords.count { |kw| content.include?(kw) }
      end

      raw = (best["content"] || best[:content]).to_s
      highlighted = highlight_keywords(raw.truncate(SNIPPET_LEN), keywords)
      "…#{highlighted}…"
    end

    def highlight_keywords(text, keywords)
      keywords.reduce(text) do |str, kw|
        str.gsub(/#{Regexp.escape(kw)}/i) { "#{HIGHLIGHT_PRE}#{$&}#{HIGHLIGHT_SUF}" }
      end
    end

    # Convert a user query string into a safe PostgreSQL tsquery.
    # Joins words with & (AND) for tighter relevance.
    def sanitized_tsquery(query)
      words = query.gsub(/[^a-zA-Z0-9\s\-']/, " ")
                   .split(/\s+/)
                   .reject { |w| w.length < 2 }
                   .first(10)
      raise ArgumentError, "Query too short or contains only stop words" if words.empty?

      words.map { |w| w.gsub(/[^a-zA-Z0-9\-']/, "") }.reject(&:empty?).join(" & ")
    end

    def parse_date(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def filter_note(agent_filter, from, to)
      parts = []
      parts << "agent=#{agent_filter}" if agent_filter
      parts << "from=#{from.strftime('%Y-%m-%d')}" if from
      parts << "to=#{to.strftime('%Y-%m-%d')}"     if to
      parts.any? ? " (#{parts.join(', ')})" : ""
    end
  end
end
