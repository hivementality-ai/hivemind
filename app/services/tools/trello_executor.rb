# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Tools
  class TrelloExecutor < BaseExecutor
    # Trello integration via REST API.
    #
    # Credentials stored in vault:
    #   trello/api_key   — Trello API key
    #   trello/token     — Trello API token
    #
    # Get credentials at: https://trello.com/power-ups/admin

    BASE_URL = "https://api.trello.com/1"

    def call
      action = input["action"].to_s.strip

      case action
      when "list_boards"      then list_boards
      when "get_board"        then get_board
      when "list_lists"       then list_lists
      when "list_cards"       then list_cards
      when "get_card"         then get_card
      when "create_card"      then create_card
      when "update_card"      then update_card
      when "move_card"        then move_card
      when "archive_card"     then archive_card
      when "add_comment"      then add_comment
      when "list_labels"      then list_labels
      when "add_label"        then add_label
      when "remove_label"     then remove_label
      when "list_members"     then list_members
      when "assign_member"    then assign_member
      when "unassign_member"  then unassign_member
      when "search"           then search
      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. Supported: list_boards, get_board, list_lists, " \
                 "list_cards, get_card, create_card, update_card, move_card, archive_card, " \
                 "add_comment, list_labels, add_label, remove_label, list_members, " \
                 "assign_member, unassign_member, search"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Trello error: #{e.message}")
    end

    private

    # ─── Board Actions ─────────────────────────────────────────────

    def list_boards
      response = api_get("/members/me/boards", filter: "open", fields: "name,url,shortUrl,dateLastActivity")
      boards = response.map do |b|
        "#{b['name']} (#{b['id']})\n  URL: #{b['shortUrl']}\n  Last activity: #{b['dateLastActivity'].to_s[0..9]}"
      end

      ServiceResponse.success(data: { output: "Your boards:\n\n#{boards.join("\n\n")}" })
    end

    def get_board
      id = require_param!("board_id")
      response = api_get("/boards/#{id}", fields: "name,desc,url,dateLastActivity", lists: "open", list_fields: "name,pos")

      lists = (response["lists"] || []).map { |l| "  - #{l['name']} (#{l['id']})" }.join("\n")
      output = "#{response['name']}\n"
      output += "Description: #{response['desc']}\n" if response["desc"].present?
      output += "URL: #{response['url']}\n"
      output += "Last activity: #{response['dateLastActivity'].to_s[0..9]}\n"
      output += "\nLists:\n#{lists}" if lists.present?

      ServiceResponse.success(data: { output: output })
    end

    # ─── List Actions ──────────────────────────────────────────────

    def list_lists
      board_id = require_param!("board_id")
      response = api_get("/boards/#{board_id}/lists", filter: "open", fields: "name,pos")

      lists = response.map { |l| "#{l['name']} (#{l['id']})" }
      ServiceResponse.success(data: { output: "Lists:\n#{lists.join("\n")}" })
    end

    # ─── Card Actions ──────────────────────────────────────────────

    def list_cards
      list_id = require_param!("list_id")
      fields = "name,desc,url,labels,due,idMembers,shortUrl,dateLastActivity"
      response = api_get("/lists/#{list_id}/cards", fields: fields)

      if response.empty?
        return ServiceResponse.success(data: { output: "No cards in this list." })
      end

      cards = response.map { |c| format_card_summary(c) }
      ServiceResponse.success(data: { output: "Cards (#{response.size}):\n\n#{cards.join("\n\n")}" })
    end

    def get_card
      card_id = require_param!("card_id")
      response = api_get("/cards/#{card_id}",
        fields: "name,desc,url,labels,due,idMembers,idList,shortUrl,dateLastActivity,closed",
        members: "true", member_fields: "fullName,username",
        list: "true", list_fields: "name",
        actions: "commentCard", actions_limit: "10")

      output = format_card_detail(response)
      ServiceResponse.success(data: { output: output })
    end

    def create_card
      list_id = require_param!("list_id")
      name = require_param!("name")

      body = { idList: list_id, name: name }
      body[:desc] = input["desc"] if input["desc"].present?
      body[:due] = input["due"] if input["due"].present?
      body[:idLabels] = input["label_ids"] if input["label_ids"].present?
      body[:pos] = input["position"] || "bottom"

      response = api_post("/cards", body)
      ServiceResponse.success(data: { output: "Created card: #{response['name']}\nID: #{response['id']}\nURL: #{response['shortUrl']}" })
    end

    def update_card
      card_id = require_param!("card_id")

      body = {}
      body[:name] = input["name"] if input["name"].present?
      body[:desc] = input["desc"] if input["desc"].present?
      body[:due] = input["due"] if input["due"].present?
      body[:closed] = input["closed"] if input.key?("closed")

      return ServiceResponse.failure(error: "No fields to update") if body.empty?

      response = api_put("/cards/#{card_id}", body)
      ServiceResponse.success(data: { output: "Updated card: #{response['name']}" })
    end

    def move_card
      card_id = require_param!("card_id")
      list_id = require_param!("list_id")

      body = { idList: list_id }
      body[:pos] = input["position"] || "bottom"

      response = api_put("/cards/#{card_id}", body)
      ServiceResponse.success(data: { output: "Moved card '#{response['name']}' to list #{list_id}" })
    end

    def archive_card
      card_id = require_param!("card_id")
      api_put("/cards/#{card_id}", { closed: true })
      ServiceResponse.success(data: { output: "Card #{card_id} archived" })
    end

    # ─── Comments ──────────────────────────────────────────────────

    def add_comment
      card_id = require_param!("card_id")
      text = require_param!("text")

      api_post("/cards/#{card_id}/actions/comments", { text: text })
      ServiceResponse.success(data: { output: "Comment added to #{card_id}" })
    end

    # ─── Labels ────────────────────────────────────────────────────

    def list_labels
      board_id = require_param!("board_id")
      response = api_get("/boards/#{board_id}/labels", fields: "name,color")

      labels = response.map { |l| "#{l['color'] || 'none'}: #{l['name'].presence || '(unnamed)'} (#{l['id']})" }
      ServiceResponse.success(data: { output: "Labels:\n#{labels.join("\n")}" })
    end

    def add_label
      card_id = require_param!("card_id")
      label_id = require_param!("label_id")

      api_post("/cards/#{card_id}/idLabels", { value: label_id })
      ServiceResponse.success(data: { output: "Label #{label_id} added to #{card_id}" })
    end

    def remove_label
      card_id = require_param!("card_id")
      label_id = require_param!("label_id")

      api_delete("/cards/#{card_id}/idLabels/#{label_id}")
      ServiceResponse.success(data: { output: "Label #{label_id} removed from #{card_id}" })
    end

    # ─── Members ───────────────────────────────────────────────────

    def list_members
      board_id = require_param!("board_id")
      response = api_get("/boards/#{board_id}/members", fields: "fullName,username")

      members = response.map { |m| "#{m['fullName']} (@#{m['username']}) — #{m['id']}" }
      ServiceResponse.success(data: { output: "Members:\n#{members.join("\n")}" })
    end

    def assign_member
      card_id = require_param!("card_id")
      member_id = require_param!("member_id")

      api_post("/cards/#{card_id}/idMembers", { value: member_id })
      ServiceResponse.success(data: { output: "Member #{member_id} assigned to #{card_id}" })
    end

    def unassign_member
      card_id = require_param!("card_id")
      member_id = require_param!("member_id")

      api_delete("/cards/#{card_id}/idMembers/#{member_id}")
      ServiceResponse.success(data: { output: "Member #{member_id} unassigned from #{card_id}" })
    end

    # ─── Search ────────────────────────────────────────────────────

    def search
      query = require_param!("query")
      board_id = input["board_id"]

      params = { query: query, modelTypes: "cards", cards_limit: 20 }
      params[:idBoards] = board_id if board_id.present?

      response = api_get("/search", **params)
      cards = (response["cards"] || []).map { |c| format_card_summary(c) }

      if cards.empty?
        ServiceResponse.success(data: { output: "No cards found for: #{query}" })
      else
        ServiceResponse.success(data: { output: "Search results for '#{query}' (#{cards.size}):\n\n#{cards.join("\n\n")}" })
      end
    end

    # ─── Formatting ────────────────────────────────────────────────

    def format_card_summary(card)
      line = "#{card['name']} (#{card['id']})"
      labels = (card["labels"] || []).map { |l| l["name"].presence || l["color"] }.compact
      line += "\n  Labels: #{labels.join(', ')}" if labels.any?
      line += "\n  Due: #{card['due'][0..9]}" if card["due"].present?
      line += "\n  URL: #{card['shortUrl']}" if card["shortUrl"].present?
      line
    end

    def format_card_detail(card)
      lines = []
      lines << "#{card['name']}"
      lines << "ID: #{card['id']}"
      lines << "URL: #{card['shortUrl']}" if card["shortUrl"]
      lines << "List: #{card.dig('list', 'name')}" if card.dig("list", "name")
      lines << "Status: #{card['closed'] ? 'Archived' : 'Open'}"

      labels = (card["labels"] || []).map { |l| l["name"].presence || l["color"] }.compact
      lines << "Labels: #{labels.join(', ')}" if labels.any?

      members = (card["members"] || []).map { |m| "#{m['fullName']} (@#{m['username']})" }
      lines << "Members: #{members.join(', ')}" if members.any?

      lines << "Due: #{card['due'][0..9]}" if card["due"].present?
      lines << ""
      lines << card["desc"] if card["desc"].present?

      comments = (card["actions"] || []).select { |a| a["type"] == "commentCard" }
      if comments.any?
        lines << ""
        lines << "Recent comments:"
        comments.each do |c|
          author = c.dig("memberCreator", "fullName") || "Unknown"
          date = c["date"].to_s[0..9]
          text = c.dig("data", "text").to_s.truncate(300)
          lines << "  #{date} — #{author}: #{text}"
        end
      end

      lines.join("\n")
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def require_param!(key)
      value = input[key].to_s.strip
      raise "#{key} is required" if value.empty?
      value
    end

    # ─── HTTP ──────────────────────────────────────────────────────

    def api_get(path, **params)
      params[:key] = api_key
      params[:token] = api_token
      query = URI.encode_www_form(params)
      request(:get, "#{path}?#{query}")
    end

    def api_post(path, body = {})
      body[:key] = api_key
      body[:token] = api_token
      request(:post, path, body)
    end

    def api_put(path, body = {})
      body[:key] = api_key
      body[:token] = api_token
      request(:put, path, body)
    end

    def api_delete(path)
      query = URI.encode_www_form(key: api_key, token: api_token)
      request(:delete, "#{path}?#{query}")
    end

    def request(method, path, body = nil)
      uri = URI("#{BASE_URL}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      req = case method
      when :get    then Net::HTTP::Get.new(uri)
      when :post   then Net::HTTP::Post.new(uri)
      when :put    then Net::HTTP::Put.new(uri)
      when :delete then Net::HTTP::Delete.new(uri)
      end

      req["Accept"] = "application/json"

      if body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end

      response = http.request(req)

      unless response.is_a?(Net::HTTPSuccess)
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

    def api_key
      @api_key ||= vault_get("trello", "api_key") || ENV["TRELLO_API_KEY"] ||
        raise("Trello API key not configured. Add it at /integrations")
    end

    def api_token
      @api_token ||= vault_get("trello", "token") || ENV["TRELLO_TOKEN"] ||
        raise("Trello token not configured. Add it at /integrations")
    end

    def vault_get(namespace, key)
      VaultEntry.find_by(namespace: namespace, key: key)&.value
    end
  end
end
