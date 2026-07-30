# frozen_string_literal: true

# Client for ClawHub (https://clawhub.ai), OpenClaw's public skill registry.
# ALL registry specifics (endpoints, JSON shapes) live here so the endpoint
# shape is swappable — the rest of the app only sees normalized hashes:
#   { slug:, name:, description:, author:, downloads:, version: }
#
# API (docs.openclaw.ai/clawhub/http-api):
#   GET /api/v1/search?q=...&limit=...        → { "results": [...] }
#   GET /api/v1/skills?sort=downloads&limit=  → { "items": [...] }
#   GET /api/v1/skills/{slug}/file?path=SKILL.md → raw markdown
module Clawhub
  class Client
    BASE_URL = ENV.fetch("CLAWHUB_URL", "https://clawhub.ai")

    class << self
      def search(query, limit: 24)
        body = get("/api/v1/search", q: query, limit: limit)
        ServiceResponse.success(data: JSON.parse(body).fetch("results", []).map { |r| normalize(r) })
      rescue StandardError => e
        unreachable(e)
      end

      # Default marketplace listing when no query is given.
      def popular(limit: 24)
        body = get("/api/v1/skills", sort: "downloads", limit: limit)
        ServiceResponse.success(data: JSON.parse(body).fetch("items", []).map { |r| normalize(r) })
      rescue StandardError => e
        unreachable(e)
      end

      # Raw SKILL.md content for a skill, ready for Skill.from_skill_md.
      def fetch_skill_md(slug)
        body = get("/api/v1/skills/#{ERB::Util.url_encode(slug)}/file", path: "SKILL.md")
        ServiceResponse.success(data: body)
      rescue StandardError => e
        unreachable(e)
      end

      private

      # Search results and catalog items have slightly different shapes;
      # normalize both.
      def normalize(entry)
        {
          slug: entry["slug"],
          name: entry["displayName"].presence || entry["slug"],
          description: entry["summary"] || entry["description"],
          author: entry["ownerHandle"],
          downloads: entry["downloads"] || entry.dig("stats", "downloads"),
          version: entry.dig("latestVersion", "version")
        }
      end

      def get(path, params)
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Hivemind/#{Hivemind::VERSION}"

        response = http.request(request)
        raise "ClawHub returned HTTP #{response.code}" unless response.code == "200"

        response.body
      end

      def unreachable(error)
        Rails.logger.warn("[Clawhub::Client] #{error.class}: #{error.message}")
        ServiceResponse.failure(error: "Couldn't reach ClawHub (#{error.message}). Try again in a minute.")
      end
    end
  end
end
