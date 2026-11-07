# frozen_string_literal: true

require "digest"
require "net/http"
require "uri"

module ScheduledTasks
  # Cheap, model-free check of a scheduled task's watch URL (web page or RSS/Atom feed).
  # Reports whether anything is new since the state stored on the task.
  class Precheck
    TIMEOUT = 5
    MAX_BYTES = 1_000_000
    MAX_ITEMS = 10
    MAX_SEEN_IDS = 200

    Result = Struct.new(:status, :items, :state, keyword_init: true)

    # @param task [ScheduledTask]
    # @return [Result] status is :changed, :unchanged or :failed
    def self.call(task)
      new(task).call
    end

    def initialize(task)
      @task = task
    end

    def call
      body = fetch(@task.precheck_url)
      feed = parse_feed(body)
      feed ? check_feed(feed) : check_page(body)
    rescue StandardError => e
      Rails.logger.warn("Precheck failed for scheduled task #{@task.id}: #{e.class}: #{e.message}")
      Result.new(status: :failed, items: [], state: nil)
    end

    private

    def fetch(url)
      uri = URI.parse(url.to_s)
      raise ArgumentError, "not an http(s) URL" unless uri.is_a?(URI::HTTP)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Hivemind/1.0"

      buffer = +""
      http.request(request) do |response|
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          buffer << chunk
          raise "response over #{MAX_BYTES} bytes" if buffer.bytesize > MAX_BYTES
        end
      end
      buffer
    end

    def parse_feed(body)
      doc = Nokogiri::XML(body) { |config| config.strict.nonet }
      doc.remove_namespaces!
      %w[rss feed RDF].include?(doc.root&.name) ? doc : nil
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def check_feed(doc)
      items = doc.xpath("//item | //entry").map { |node| feed_item(node) }.select { |item| item[:id].present? }
      seen = Array(@task.precheck_state["ids"])
      fresh = items.reject { |item| seen.include?(item[:id]) }
      state = { "ids" => (items.map { |item| item[:id] } + seen).uniq.first(MAX_SEEN_IDS) }
      Result.new(status: fresh.empty? ? :unchanged : :changed, items: fresh.first(MAX_ITEMS), state: state)
    end

    def feed_item(node)
      link = node.at_xpath("link/@href")&.value.presence || node.at_xpath("link")&.text&.strip
      title = node.at_xpath("title")&.text&.strip
      id = node.at_xpath("guid | id")&.text&.strip.presence || link
      { id: id, title: title.presence || link, link: link }
    end

    def check_page(body)
      text = body.to_s.dup.force_encoding("UTF-8").scrub
      text = text.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, " ").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      digest = Digest::SHA256.hexdigest(text)
      same = @task.precheck_state["digest"] == digest
      Result.new(status: same ? :unchanged : :changed, items: [], state: { "digest" => digest })
    end
  end
end
