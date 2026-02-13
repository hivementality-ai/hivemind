# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Tools
  class BrowserExecutor < BaseExecutor
    # Supports: navigate, screenshot, content, click, type, evaluate
    def call
      action = input["action"].to_s.strip
      url = input["url"].to_s.strip

      case action
      when "navigate", "get", ""
        return ServiceResponse.failure(error: "No URL provided") if url.empty?
        navigate_and_extract(url)
      when "screenshot"
        return ServiceResponse.failure(error: "No URL provided") if url.empty?
        screenshot(url)
      else
        ServiceResponse.failure(error: "Unknown browser action: #{action}. Supported: navigate, screenshot")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Browser error: #{e.message}")
    end

    private

    def navigate_and_extract(url)
      # Use the Playwright server via CDP or fall back to a simple HTTP fetch with JS rendering
      script = build_script(url, extract: true)
      result = run_in_browser(script)

      if result[:success]
        output = []
        output << "Title: #{result[:title]}" if result[:title]
        output << "URL: #{result[:url]}" if result[:url]
        output << ""
        output << result[:content].to_s.truncate(30_000)
        ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
      else
        ServiceResponse.failure(error: result[:error])
      end
    end

    def screenshot(url)
      script = build_script(url, screenshot: true)
      result = run_in_browser(script)

      if result[:success]
        ServiceResponse.success(data: {
          output: "Screenshot saved: #{result[:path]}\nTitle: #{result[:title]}",
          exit_code: 0
        })
      else
        ServiceResponse.failure(error: result[:error])
      end
    end

    def build_script(url, extract: false, screenshot: false)
      <<~JS
        const { chromium } = require('playwright');
        (async () => {
          const browser = await chromium.launch({ headless: true });
          const page = await browser.newPage();
          try {
            await page.goto('#{url.gsub("'", "\\\\'")}', { waitUntil: 'domcontentloaded', timeout: 30000 });
            const title = await page.title();
            const url = page.url();
            #{extract ? "const content = await page.evaluate(() => document.body.innerText);" : ""}
            #{screenshot ? "await page.screenshot({ path: '/tmp/screenshot.png', fullPage: false });" : ""}
            console.log(JSON.stringify({
              success: true,
              title,
              url,
              #{extract ? "content," : ""}
              #{screenshot ? "path: '/tmp/screenshot.png'," : ""}
            }));
          } catch (e) {
            console.log(JSON.stringify({ success: false, error: e.message }));
          } finally {
            await browser.close();
          }
        })();
      JS
    end

    def run_in_browser(script)
      # Write script to a temp file and execute in the browser container
      script_path = "/tmp/browser_script_#{SecureRandom.hex(8)}.js"
      File.write(script_path, script)

      # Execute via docker exec (browser container has Node + Playwright)
      stdout, stderr, status = Open3.capture3(
        "docker", "exec", "-i", "hivemind-browser-1",
        "node", "-e", script,
        timeout: 35
      )

      if status.success? && stdout.present?
        JSON.parse(stdout.strip.lines.last).symbolize_keys
      else
        { success: false, error: stderr.presence || "Browser execution failed" }
      end
    rescue JSON::ParserError => e
      { success: false, error: "Failed to parse browser output: #{stdout&.truncate(200)}" }
    rescue StandardError => e
      { success: false, error: e.message }
    ensure
      FileUtils.rm_f(script_path) if script_path
    end
  end
end
