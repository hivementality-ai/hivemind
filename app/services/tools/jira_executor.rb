# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"

module Tools
  class JiraExecutor < BaseExecutor
    # Jira Cloud integration via REST API v3.
    #
    # Credentials stored in vault:
    #   jira/base_url    — https://your-domain.atlassian.net
    #   jira/email       — user@example.com
    #   jira/api_token   — Atlassian API token

    def call
      action = input["action"].to_s.strip

      case action
      when "get_issue"
        get_issue
      when "search"
        search_issues
      when "create_issue"
        create_issue
      when "update_issue"
        update_issue
      when "add_comment"
        add_comment
      when "list_comments"
        list_comments
      when "transition"
        transition_issue
      when "list_transitions"
        list_transitions
      when "assign"
        assign_issue
      when "list_projects"
        list_projects
      when "my_issues"
        my_issues
      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. Supported: get_issue, search, create_issue, update_issue, " \
                 "add_comment, list_comments, transition, list_transitions, assign, list_projects, my_issues"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Jira error: #{e.message}")
    end

    private

    # ─── Actions ───────────────────────────────────────────────────

    def get_issue
      key = input["key"].to_s.strip
      return ServiceResponse.failure(error: "No issue key provided") if key.empty?

      response = api_get("/rest/api/3/issue/#{key}?expand=renderedFields")
      issue = parse_issue(response)

      ServiceResponse.success(data: { output: format_issue(issue), exit_code: 0 })
    end

    def search_issues
      jql = input["jql"].to_s.strip
      return ServiceResponse.failure(error: "No JQL query provided") if jql.empty?

      max_results = (input["limit"] || 20).to_i.clamp(1, 50)
      response = api_get("/rest/api/3/search?jql=#{URI.encode_www_form_component(jql)}&maxResults=#{max_results}")

      issues = (response["issues"] || []).map { |i| parse_issue_summary(i) }
      output = "Search: #{jql}\nFound: #{response['total']} (showing #{issues.size})\n\n"
      output += issues.map { |i| "#{i[:key]} [#{i[:status]}] #{i[:summary]} (#{i[:assignee]})" }.join("\n")

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def create_issue
      project = input["project"].to_s.strip
      summary = input["summary"].to_s.strip
      issue_type = input["issue_type"].to_s.strip.presence || "Task"

      return ServiceResponse.failure(error: "project and summary required") if project.empty? || summary.empty?

      body = {
        fields: {
          project: { key: project },
          summary: summary,
          issuetype: { name: issue_type }
        }
      }
      body[:fields][:description] = adf_paragraph(input["description"]) if input["description"].present?
      body[:fields][:parent] = { key: input["parent"] } if input["parent"].present?
      body[:fields][:assignee] = { accountId: input["assignee_id"] } if input["assignee_id"].present?
      body[:fields][:priority] = { name: input["priority"] } if input["priority"].present?
      body[:fields][:labels] = input["labels"].split(",").map(&:strip) if input["labels"].present?

      response = api_post("/rest/api/3/issue", body)
      ServiceResponse.success(data: { output: "Created #{response['key']}: #{summary}\nURL: #{base_url}/browse/#{response['key']}", exit_code: 0 })
    end

    def update_issue
      key = input["key"].to_s.strip
      return ServiceResponse.failure(error: "No issue key provided") if key.empty?

      fields = {}
      fields[:summary] = input["summary"] if input["summary"].present?
      fields[:description] = adf_paragraph(input["description"]) if input["description"].present?
      fields[:priority] = { name: input["priority"] } if input["priority"].present?
      fields[:labels] = input["labels"].split(",").map(&:strip) if input["labels"].present?
      fields[:assignee] = { accountId: input["assignee_id"] } if input["assignee_id"].present?

      return ServiceResponse.failure(error: "No fields to update") if fields.empty?

      api_put("/rest/api/3/issue/#{key}", { fields: fields })
      ServiceResponse.success(data: { output: "Updated #{key}", exit_code: 0 })
    end

    def add_comment
      key = input["key"].to_s.strip
      body_text = input["body"].to_s.strip

      return ServiceResponse.failure(error: "key and body required") if key.empty? || body_text.empty?

      api_post("/rest/api/3/issue/#{key}/comment", { body: adf_paragraph(body_text) })
      ServiceResponse.success(data: { output: "Comment added to #{key}", exit_code: 0 })
    end

    def list_comments
      key = input["key"].to_s.strip
      return ServiceResponse.failure(error: "No issue key provided") if key.empty?

      response = api_get("/rest/api/3/issue/#{key}/comment?orderBy=-created&maxResults=10")
      comments = (response["comments"] || []).map do |c|
        author = c.dig("author", "displayName") || "Unknown"
        created = c["created"].to_s[0..9]
        body = extract_text(c["body"])
        "#{created} — #{author}: #{body.truncate(300)}"
      end

      output = "Comments on #{key} (#{comments.size}):\n\n#{comments.join("\n\n")}"
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def transition_issue
      key = input["key"].to_s.strip
      transition_name = input["transition"].to_s.strip

      return ServiceResponse.failure(error: "key and transition required") if key.empty? || transition_name.empty?

      # Find transition ID by name
      transitions_response = api_get("/rest/api/3/issue/#{key}/transitions")
      transition = (transitions_response["transitions"] || []).find do |t|
        t["name"].downcase == transition_name.downcase
      end
      return ServiceResponse.failure(error: "Transition '#{transition_name}' not available. Use list_transitions to see options.") unless transition

      api_post("/rest/api/3/issue/#{key}/transitions", { transition: { id: transition["id"] } })
      ServiceResponse.success(data: { output: "#{key} transitioned to: #{transition_name}", exit_code: 0 })
    end

    def list_transitions
      key = input["key"].to_s.strip
      return ServiceResponse.failure(error: "No issue key provided") if key.empty?

      response = api_get("/rest/api/3/issue/#{key}/transitions")
      transitions = (response["transitions"] || []).map { |t| "#{t['id']}: #{t['name']}" }

      ServiceResponse.success(data: { output: "Available transitions for #{key}:\n#{transitions.join("\n")}", exit_code: 0 })
    end

    def assign_issue
      key = input["key"].to_s.strip
      assignee_id = input["assignee_id"].to_s.strip

      return ServiceResponse.failure(error: "key and assignee_id required") if key.empty? || assignee_id.empty?

      api_put("/rest/api/3/issue/#{key}/assignee", { accountId: assignee_id })
      ServiceResponse.success(data: { output: "#{key} assigned to #{assignee_id}", exit_code: 0 })
    end

    def list_projects
      response = api_get("/rest/api/3/project?maxResults=50&orderBy=name")
      projects = (response.is_a?(Array) ? response : response["values"] || []).map do |p|
        "#{p['key']}: #{p['name']}"
      end

      ServiceResponse.success(data: { output: "Projects:\n#{projects.join("\n")}", exit_code: 0 })
    end

    def my_issues
      max_results = (input["limit"] || 20).to_i.clamp(1, 50)
      jql = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"
      response = api_get("/rest/api/3/search?jql=#{URI.encode_www_form_component(jql)}&maxResults=#{max_results}")

      issues = (response["issues"] || []).map { |i| parse_issue_summary(i) }
      output = "My open issues (#{response['total']} total, showing #{issues.size}):\n\n"
      output += issues.map { |i| "#{i[:key]} [#{i[:status]}] #{i[:summary]}" }.join("\n")

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    # ─── Parsing ───────────────────────────────────────────────────

    def parse_issue(data)
      fields = data["fields"] || {}
      {
        key: data["key"],
        summary: fields["summary"],
        status: fields.dig("status", "name"),
        priority: fields.dig("priority", "name"),
        issue_type: fields.dig("issuetype", "name"),
        assignee: fields.dig("assignee", "displayName") || "Unassigned",
        reporter: fields.dig("reporter", "displayName"),
        created: fields["created"].to_s[0..9],
        updated: fields["updated"].to_s[0..9],
        labels: (fields["labels"] || []).join(", "),
        description: extract_text(fields["description"]),
        parent: fields.dig("parent", "key"),
        subtasks: (fields["subtasks"] || []).map { |s| "#{s['key']}: #{s.dig('fields', 'summary')}" }
      }
    end

    def parse_issue_summary(data)
      fields = data["fields"] || {}
      {
        key: data["key"],
        summary: fields["summary"],
        status: fields.dig("status", "name"),
        assignee: fields.dig("assignee", "displayName") || "Unassigned",
        priority: fields.dig("priority", "name")
      }
    end

    def format_issue(issue)
      lines = []
      lines << "#{issue[:key]}: #{issue[:summary]}"
      lines << "Type: #{issue[:issue_type]} | Status: #{issue[:status]} | Priority: #{issue[:priority]}"
      lines << "Assignee: #{issue[:assignee]} | Reporter: #{issue[:reporter]}"
      lines << "Created: #{issue[:created]} | Updated: #{issue[:updated]}"
      lines << "Parent: #{issue[:parent]}" if issue[:parent].present?
      lines << "Labels: #{issue[:labels]}" if issue[:labels].present?
      lines << ""
      lines << issue[:description].to_s.truncate(5000) if issue[:description].present?
      lines << ""
      lines << "Subtasks: #{issue[:subtasks].join(', ')}" if issue[:subtasks].any?
      lines.join("\n")
    end

    # ─── ADF helpers ───────────────────────────────────────────────

    def adf_paragraph(text)
      {
        type: "doc",
        version: 1,
        content: text.to_s.split("\n\n").map do |para|
          {
            type: "paragraph",
            content: [ { type: "text", text: para } ]
          }
        end
      }
    end

    def extract_text(adf)
      return "" unless adf.is_a?(Hash) && adf["content"]

      adf["content"].map { |node| extract_node_text(node) }.join("\n\n").strip
    end

    def extract_node_text(node)
      return "" unless node.is_a?(Hash)

      case node["type"]
      when "text"
        node["text"].to_s
      when "hardBreak"
        "\n"
      when "paragraph", "heading", "listItem", "blockquote"
        (node["content"] || []).map { |n| extract_node_text(n) }.join
      when "bulletList", "orderedList"
        (node["content"] || []).map.with_index do |item, i|
          prefix = node["type"] == "orderedList" ? "#{i + 1}. " : "- "
          "#{prefix}#{extract_node_text(item)}"
        end.join("\n")
      when "codeBlock"
        code = (node["content"] || []).map { |n| extract_node_text(n) }.join
        "```\n#{code}\n```"
      else
        (node["content"] || []).map { |n| extract_node_text(n) }.join
      end
    end

    # ─── HTTP ──────────────────────────────────────────────────────

    def api_get(path)
      request(:get, path)
    end

    def api_post(path, body)
      request(:post, path, body)
    end

    def api_put(path, body)
      request(:put, path, body)
    end

    def request(method, path, body = nil)
      uri = URI("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      req = case method
      when :get    then Net::HTTP::Get.new(uri)
      when :post   then Net::HTTP::Post.new(uri)
      when :put    then Net::HTTP::Put.new(uri)
      end

      req["Authorization"] = "Basic #{Base64.strict_encode64("#{jira_email}:#{jira_token}")}"
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"

      req.body = body.to_json if body

      response = http.request(req)

      unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNoContent)
        error_body = begin
          JSON.parse(response.body)
        rescue StandardError
          response.body
        end
        raise "HTTP #{response.code}: #{error_body}"
      end

      return {} if response.body.blank?

      JSON.parse(response.body)
    end

    # ─── Credentials ───────────────────────────────────────────────

    def base_url
      @base_url ||= (vault_get("jira", "base_url") || ENV["JIRA_BASE_URL"]).to_s.chomp("/")
    end

    def jira_email
      @jira_email ||= vault_get("jira", "email") || ENV["JIRA_EMAIL"]
    end

    def jira_token
      @jira_token ||= vault_get("jira", "api_token") || ENV["JIRA_API_TOKEN"]
    end

    def vault_get(namespace, key)
      entry = VaultEntry.find_by(namespace: namespace, key: key)
      entry&.value
    end
  end
end
