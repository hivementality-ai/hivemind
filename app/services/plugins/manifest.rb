# frozen_string_literal: true

module Plugins
  class Manifest
    REQUIRED_FIELDS = %w[name version].freeze
    OPTIONAL_FIELDS = %w[description author extension_points dependencies].freeze
    VALID_EXTENSION_TYPES = %w[channel tool memory hook].freeze

    attr_reader :name, :version, :description, :author, :extension_points, :dependencies, :raw

    def self.load(path:)
      raise ArgumentError, "Manifest not found: #{path}" unless File.exist?(path)

      data = YAML.safe_load(File.read(path), permitted_classes: [Symbol])
      new(data: data, path: path)
    end

    def initialize(data:, path: nil)
      @raw = data || {}
      @path = path
      validate!
      parse!
    end

    def valid?
      @errors.empty?
    end

    def errors
      @errors.dup
    end

    private

    def validate!
      @errors = []

      REQUIRED_FIELDS.each do |field|
        @errors << "Missing required field: #{field}" if @raw[field].to_s.strip.empty?
      end

      validate_extension_points! if @raw["extension_points"].is_a?(Array)
      validate_dependencies! if @raw["dependencies"].is_a?(Hash)
    end

    def validate_extension_points!
      @raw["extension_points"].each_with_index do |ext, i|
        unless ext.is_a?(Hash)
          @errors << "extension_points[#{i}] must be a hash"
          next
        end

        @errors << "extension_points[#{i}] missing type" if ext["type"].to_s.strip.empty?
        @errors << "extension_points[#{i}] missing id" if ext["id"].to_s.strip.empty?
        @errors << "extension_points[#{i}] missing class_name" if ext["class_name"].to_s.strip.empty?

        if ext["type"].present? && !VALID_EXTENSION_TYPES.include?(ext["type"])
          @errors << "extension_points[#{i}] invalid type: #{ext['type']} (valid: #{VALID_EXTENSION_TYPES.join(', ')})"
        end
      end
    end

    def validate_dependencies!
      deps = @raw["dependencies"]
      if deps.key?("gems") && !deps["gems"].is_a?(Array)
        @errors << "dependencies.gems must be an array"
      end
      if deps.key?("npm_packages") && !deps["npm_packages"].is_a?(Array)
        @errors << "dependencies.npm_packages must be an array"
      end
    end

    def parse!
      raise ArgumentError, "Invalid manifest: #{@errors.join(', ')}" unless valid?

      @name = @raw["name"]
      @version = @raw["version"]
      @description = @raw["description"]
      @author = @raw["author"]
      @extension_points = (@raw["extension_points"] || []).map do |ext|
        ExtensionPoint.new(
          type: ext["type"],
          id: ext["id"],
          class_name: ext["class_name"],
          config_schema: ext["config_schema"]
        )
      end
      @dependencies = Dependencies.new(
        gems: @raw.dig("dependencies", "gems") || [],
        npm_packages: @raw.dig("dependencies", "npm_packages") || []
      )
    end

    ExtensionPoint = Struct.new(:type, :id, :class_name, :config_schema, keyword_init: true)
    Dependencies = Struct.new(:gems, :npm_packages, keyword_init: true)
  end
end
