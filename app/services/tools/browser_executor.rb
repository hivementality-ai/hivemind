# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Tools
  class BrowserExecutor < BaseExecutor
    SIDECAR_URL = ENV.fetch("BROWSER_SIDECAR_URL", "http://browser-sidecar:8000")
    TIMEOUT = 35

    # Unified browser tool — agents interact via action dispatch.
    #
    # Actions:
    #   navigate  — go to URL, return page state with interactive elements
    #   state     — get current page state (elements, text)
    #   click     — click element by index
    #   type      — type text into element by index
    #   scroll    — scroll up/down
    #   keys      — send keyboard shortcut (Enter, Escape, etc.)
    #   screenshot — capture page as image
    #   extract   — get full page text content
    #   done      — close browser session
    def call
      action = input["action"].to_s.strip.downcase
      action = "navigate" if action.empty?

      # Auto-manage sessions: create on first use, store in Redis keyed by session.
      ensure_session! unless action == "done"

      case action
      when "navigate", "get"
        url = input["url"].to_s.strip
        return ServiceResponse.failure(error: "No URL provided") if url.empty?

        result = post("session/#{session_id}/navigate", { url: url })
        format_state_response(result, prefix: "Navigated to #{url}")

      when "state"
        result = post("session/#{session_id}/state", {})
        format_state_response(result)

      when "click"
        index = input["index"].to_i
        return ServiceResponse.failure(error: "No element index provided") if index < 1

        result = post("session/#{session_id}/click", { index: index })
        format_state_response(result, prefix: "Clicked element #{index}")

      when "type"
        index = input["index"].to_i
        text  = input["text"].to_s
        clear = input.fetch("clear", true)
        return ServiceResponse.failure(error: "No element index provided") if index < 1
        return ServiceResponse.failure(error: "No text provided") if text.empty?

        result = post("session/#{session_id}/type", { index: index, text: text, clear: clear })
        format_state_response(result, prefix: "Typed into element #{index}")

      when "scroll"
        direction = input.fetch("direction", "down")
        pages     = input.fetch("pages", 1.0).to_f
        result    = post("session/#{session_id}/scroll", { direction: direction, pages: pages })
        format_state_response(result, prefix: "Scrolled #{direction}")

      when "keys"
        keys = input["keys"].to_s.strip
        return ServiceResponse.failure(error: "No keys provided") if keys.empty?

        result = post("session/#{session_id}/keys", { keys: keys })
        format_state_response(result, prefix: "Sent keys: #{keys}")

      when "screenshot"
        result = post("session/#{session_id}/screenshot", {})
        if result["success"]
          path = save_screenshot(result["screenshot_base64"])
          ServiceResponse.success(data: {
            output: "Screenshot saved: #{path}\nURL: #{result['url']}\nTitle: #{result['title']}",
            exit_code: 0
          })
        else
          ServiceResponse.failure(error: result["error"] || "Screenshot failed")
        end

      when "extract"
        result = post("session/#{session_id}/extract", {})
        if result["success"]
          output = "Title: #{result['title']}\nURL: #{result['url']}\n\n#{result['content']}"
          ServiceResponse.success(data: { output: output.truncate(30_000), exit_code: 0 })
        else
          ServiceResponse.failure(error: result["error"] || "Extract failed")
        end

      when "done", "close"
        delete("session/#{session_id}") if session_id
        clear_session!
        ServiceResponse.success(data: { output: "Browser session closed.", exit_code: 0 })

      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. " \
                 "Available: navigate, state, click, type, scroll, keys, screenshot, extract, done"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Browser error: #{e.message}")
    end

    private

    # ── Session management ────────────────────────────────────────────────────
    # Store session_id in Redis keyed by Hivemind session so multi-turn
    # browser interactions persist across tool calls within the same chat.

    def session_id
      @session_id ||= redis&.get(session_key)
    end

    def ensure_session!
      return if session_id.present?

      result = post("session/create", {
        viewport_width: 1280,
        viewport_height: 720
      })

      unless result["session_id"]
        raise "Failed to create browser session: #{result['error'] || 'unknown error'}"
      end

      @session_id = result["session_id"]
      redis&.set(session_key, @session_id, ex: 300) # 5 min TTL, matches sidecar
    end

    def clear_session!
      redis&.del(session_key)
      @session_id = nil
    end

    def session_key
      hivemind_session = config[:session]
      sid = hivemind_session&.id || "global"
      "browser_session:#{sid}"
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://cache:6379/0"))
    rescue StandardError
      nil
    end

    # ── Response formatting ───────────────────────────────────────────────────

    def format_state_response(result, prefix: nil)
      if result["success"] && result["state"]
        state  = result["state"]
        output = []
        output << prefix if prefix
        output << "URL: #{state['url']}"
        output << "Title: #{state['title']}"
        output << "Scroll: #{state['scroll_y']}/#{state['page_height']}px"
        output << ""

        if state["elements"].present?
          output << "Interactive elements:"
          state["elements"].each do |el|
            output << "  [#{el['index']}] #{format_element(el)}"
          end
        else
          output << "(No interactive elements found)"
        end

        output << ""
        output << "Page text: #{state['text_summary']}" if state["text_summary"].present?

        ServiceResponse.success(data: { output: output.join("\n").truncate(30_000), exit_code: 0 })
      elsif result["success"]
        ServiceResponse.success(data: { output: result["message"] || "OK", exit_code: 0 })
      else
        ServiceResponse.failure(error: result["error"] || "Browser action failed")
      end
    end

    def format_element(el)
      parts = [el["tag"]]
      parts << "type=#{el['type']}"                         if el["type"]
      parts << "name=#{el['name']}"                         if el["name"]
      parts << "role=#{el['role']}"                         if el["role"]
      parts << "\"#{el['text'].truncate(60)}\""             if el["text"]
      parts << "placeholder=\"#{el['placeholder']}\""       if el["placeholder"]
      parts << "value=\"#{el['value']}\""                   if el["value"]
      parts << "→ #{el['href'].truncate(80)}"               if el["href"]
      parts << "(#{el['aria_label']})"                      if el["aria_label"]
      parts.join(" ")
    end

    # ── HTTP helpers ──────────────────────────────────────────────────────────

    def post(path, body)
      request_json(:post, path, body)
    end

    def delete(path)
      request_json(:delete, path, nil)
    end

    def request_json(method, path, body)
      uri  = URI.parse("#{SIDECAR_URL}/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = TIMEOUT

      req = if method == :post
        Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" }).tap do |r|
          r.body = body.to_json if body
        end
      else
        Net::HTTP::Delete.new(uri.path)
      end

      response = http.request(req)
      JSON.parse(response.body)
    rescue JSON::ParserError
      { "success" => false, "error" => "Invalid response from browser sidecar" }
    rescue Errno::ECONNREFUSED
      { "success" => false, "error" => "Browser sidecar not running. Start with: docker compose up browser-sidecar" }
    rescue Net::ReadTimeout
      { "success" => false, "error" => "Browser action timed out" }
    rescue StandardError => e
      { "success" => false, "error" => "Browser sidecar error: #{e.message}" }
    end

    def save_screenshot(base64_data)
      path = "/tmp/screenshot_#{SecureRandom.hex(8)}.png"
      File.binwrite(path, Base64.decode64(base64_data))
      path
    end
  end
end
