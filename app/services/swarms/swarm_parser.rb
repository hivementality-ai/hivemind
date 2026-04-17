# frozen_string_literal: true

module Swarms
  # Entry point for loading a .swarm.json file.
  #
  # Usage:
  #   result = SwarmParser.call(path: "/path/to/team.swarm.json")
  #   result = SwarmParser.call(json: raw_json_string)
  #
  # Returns a ServiceResponse. On success, `result.payload` is a SwarmDocument.
  # On failure, `result.message` describes the error and `result.payload[:errors]`
  # contains the array of validation error strings.
  class SwarmParser
    MAX_FILE_SIZE = 5.megabytes

    def self.call(**kwargs)
      new(**kwargs).call
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

      validate_and_build(parsed)
    end

    private

    def load_json
      if @path.present?
        load_from_path
      elsif @json.present?
        @json
      else
        ServiceResponse.error(message: "Must provide path: or json:")
      end
    end

    def load_from_path
      unless @path.end_with?(".swarm.json")
        return ServiceResponse.error(message: "File must have .swarm.json extension")
      end

      unless File.exist?(@path)
        return ServiceResponse.error(message: "File not found: #{@path}")
      end

      size = File.size(@path)
      if size > MAX_FILE_SIZE
        return ServiceResponse.error(message: "File exceeds 5MB limit (#{size} bytes)")
      end

      File.read(@path)
    rescue Errno::EACCES => e
      ServiceResponse.error(message: "Permission denied reading file: #{e.message}")
    end

    def parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError => e
      ServiceResponse.error(message: "Invalid JSON: #{e.message}")
    end

    def validate_and_build(parsed)
      result = SwarmSchema.new.validate(parsed)

      if result.invalid?
        return ServiceResponse.error(
          message: "Swarm file is invalid",
          payload: { errors: result.errors }
        )
      end

      document = build_document(parsed)
      ServiceResponse.success(payload: document)
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
        tags:             Array(h[:tags]),
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
        variables:        build_variables(h[:variables]),
        workspace_files:  normalize_array(h[:workspace_files]),
        scheduled_tasks:  normalize_array(h[:scheduled_tasks]),
        heartbeat_config: h[:heartbeat_config].presence
      )
    end

    def normalize_array(value)
      return [] if value.nil?

      Array(value)
    end

    def build_variables(raw)
      return {} if raw.nil?

      raw.each_with_object({}) do |(key, definition), acc|
        acc[key.to_s] = SwarmDocument::SwarmVariable.from_hash(definition)
      end
    end
  end
end
