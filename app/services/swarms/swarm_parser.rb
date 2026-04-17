# frozen_string_literal: true

module Swarms
  # Parses a .swarm.json file (path or raw JSON string) into a SwarmDocument.
  #
  # Returns a ServiceResponse:
  #   success: data is a SwarmDocument
  #   failure: error is a human-readable message
  #
  # Usage:
  #   result = SwarmParser.call(path: "/tmp/team.swarm.json")
  #   result = SwarmParser.call(json: raw_json_string)
  #
  #   if result.success?
  #     doc = result.data   # => SwarmDocument
  #   else
  #     Rails.logger.error(result.error)
  #   end
  class SwarmParser
    MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024 # 5 MB per spec

    def self.call(path: nil, json: nil)
      new(path:, json:).call
    end

    def initialize(path: nil, json: nil)
      @path = path
      @json = json
    end

    def call
      raw_json = load_json
      return raw_json if raw_json.is_a?(ServiceResponse)

      parsed = parse_json(raw_json)
      return parsed if parsed.is_a?(ServiceResponse)

      validation = SwarmSchema.validate(parsed)
      return ServiceResponse.failure(error: validation_error_message(validation)) if validation.invalid?

      ServiceResponse.success(data: build_document(parsed))
    rescue StandardError => e
      ServiceResponse.failure(error: "Unexpected error parsing swarm file: #{e.message}")
    end

    private

    attr_reader :path, :json

    def load_json
      if path.present?
        load_from_path(path)
      elsif json.present?
        json
      else
        ServiceResponse.failure(error: "Either path: or json: must be provided")
      end
    end

    def load_from_path(file_path)
      unless File.exist?(file_path)
        return ServiceResponse.failure(error: "File not found: #{file_path}")
      end

      unless File.extname(file_path).end_with?(".json")
        return ServiceResponse.failure(error: "File must have a .json extension (got: #{File.extname(file_path)})")
      end

      size = File.size(file_path)
      if size > MAX_FILE_SIZE_BYTES
        return ServiceResponse.failure(error: "File exceeds maximum size of 5 MB (got #{size} bytes)")
      end

      File.read(file_path)
    rescue SystemCallError => e
      ServiceResponse.failure(error: "Could not read file '#{file_path}': #{e.message}")
    end

    def parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError => e
      ServiceResponse.failure(error: "Invalid JSON: #{e.message}")
    end

    def validation_error_message(validation)
      "Invalid .swarm.json: #{validation.errors.join('; ')}"
    end

    def build_document(parsed)
      h = parsed.with_indifferent_access

      SwarmDocument.new(
        swarm_version:    h[:swarm_version],
        name:             h[:name],
        slug:             h[:slug].presence,
        description:      h[:description].presence,
        author:           SwarmDocument::SwarmAuthor.from_hash(h[:author]),
        version:          h[:version].presence,
        license:          h[:license].presence,
        tags:             Array(h[:tags]).map(&:to_s),
        icon:             h[:icon].presence,
        homepage:         h[:homepage].presence,
        requires:         SwarmDocument::SwarmRequirements.from_hash(h[:requires]),
        team:             SwarmDocument::SwarmTeam.from_hash(h[:team]),
        agents:           normalize_array(h[:agents]),
        skills:           normalize_array(h[:skills]),
        tools:            normalize_array(h[:tools]),
        channels:         normalize_array(h[:channels]),
        mcp_servers:      normalize_array(h[:mcp_servers]),
        api_integrations: normalize_array(h[:api_integrations]),
        variables:        build_variables(h[:variables])
      )
    end

    def normalize_array(raw)
      Array(raw).map { |item| item.with_indifferent_access }
    end

    def build_variables(raw)
      return {} if raw.nil?

      raw.each_with_object({}) do |(key, definition), acc|
        acc[key.to_s] = SwarmDocument::SwarmVariable.from_hash(definition)
      end
    end
  end
end
