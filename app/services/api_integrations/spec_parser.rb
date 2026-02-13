# frozen_string_literal: true

module ApiIntegrations
  class SpecParser
    # Parses OpenAPI 3.x / Swagger 2.x specs into a normalized endpoint list.
    # Accepts JSON or YAML string, or a Hash.
    #
    # Returns:
    #   {
    #     title: "Petstore API",
    #     description: "...",
    #     base_url: "https://api.example.com/v1",
    #     spec_format: "openapi",
    #     endpoints: [
    #       {
    #         path: "/pets",
    #         method: "get",
    #         operation_id: "listPets",
    #         summary: "List all pets",
    #         description: "...",
    #         parameters: [...],
    #         request_body: { ... },
    #         responses: { ... }
    #       }
    #     ]
    #   }

    def self.call(spec_input:)
      new(spec_input:).call
    end

    def initialize(spec_input:)
      @raw = spec_input
    end

    def call
      spec = parse_input
      return ServiceResponse.failure(error: "Could not parse spec") unless spec.is_a?(Hash)

      if spec["openapi"]&.start_with?("3")
        parse_openapi_3(spec)
      elsif spec["swagger"]&.start_with?("2")
        parse_swagger_2(spec)
      else
        # Try to treat as a generic spec
        parse_generic(spec)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Spec parse error: #{e.message}")
    end

    private

    def parse_input
      case @raw
      when Hash
        @raw
      when String
        # Try JSON first, then YAML
        begin
          JSON.parse(@raw)
        rescue JSON::ParserError
          YAML.safe_load(@raw, permitted_classes: [Date, Time])
        end
      else
        nil
      end
    end

    # ─── OpenAPI 3.x ──────────────────────────────────────────────

    def parse_openapi_3(spec)
      info = spec["info"] || {}
      servers = spec["servers"] || []
      base_url = servers.first&.dig("url") || ""

      endpoints = []
      (spec["paths"] || {}).each do |path, methods|
        next unless methods.is_a?(Hash)

        %w[get post put patch delete head options].each do |method|
          op = methods[method]
          next unless op.is_a?(Hash)

          endpoints << build_endpoint(
            path: path,
            method: method,
            op: op,
            spec: spec
          )
        end
      end

      ServiceResponse.success(data: {
        title: info["title"],
        description: info["description"],
        base_url: base_url,
        spec_format: "openapi",
        spec_data: spec,
        endpoints: endpoints
      })
    end

    # ─── Swagger 2.x ─────────────────────────────────────────────

    def parse_swagger_2(spec)
      info = spec["info"] || {}
      host = spec["host"] || ""
      base_path = spec["basePath"] || ""
      schemes = spec["schemes"] || ["https"]
      base_url = "#{schemes.first}://#{host}#{base_path}"

      endpoints = []
      (spec["paths"] || {}).each do |path, methods|
        next unless methods.is_a?(Hash)

        %w[get post put patch delete head options].each do |method|
          op = methods[method]
          next unless op.is_a?(Hash)

          endpoints << build_endpoint(
            path: path,
            method: method,
            op: op,
            spec: spec
          )
        end
      end

      ServiceResponse.success(data: {
        title: info["title"],
        description: info["description"],
        base_url: base_url,
        spec_format: "swagger",
        spec_data: spec,
        endpoints: endpoints
      })
    end

    # ─── Generic ──────────────────────────────────────────────────

    def parse_generic(spec)
      # Best-effort: look for common patterns
      endpoints = []

      if spec["endpoints"].is_a?(Array)
        spec["endpoints"].each do |ep|
          endpoints << {
            "path" => ep["path"] || ep["url"],
            "method" => (ep["method"] || "get").downcase,
            "operation_id" => ep["operation_id"] || ep["name"],
            "summary" => ep["summary"] || ep["description"],
            "description" => ep["description"],
            "parameters" => ep["parameters"] || [],
            "request_body" => ep["request_body"] || ep["body"],
            "responses" => ep["responses"] || {}
          }
        end
      end

      ServiceResponse.success(data: {
        title: spec["title"] || spec["name"],
        description: spec["description"],
        base_url: spec["base_url"] || spec["baseUrl"] || "",
        spec_format: "custom",
        spec_data: spec,
        endpoints: endpoints
      })
    end

    # ─── Helpers ──────────────────────────────────────────────────

    def build_endpoint(path:, method:, op:, spec:)
      params = (op["parameters"] || []).map do |p|
        {
          "name" => p["name"],
          "in" => p["in"],          # query, path, header, cookie
          "required" => p["required"] || false,
          "type" => resolve_type(p["schema"] || p, spec),
          "description" => p["description"]
        }
      end

      request_body = nil
      if op["requestBody"]
        content = op["requestBody"]["content"] || {}
        json_schema = content.dig("application/json", "schema")
        request_body = {
          "required" => op["requestBody"]["required"] || false,
          "content_type" => content.keys.first || "application/json",
          "schema" => resolve_schema(json_schema, spec)
        }
      end

      {
        "path" => path,
        "method" => method,
        "operation_id" => op["operationId"],
        "summary" => op["summary"],
        "description" => op["description"],
        "parameters" => params,
        "request_body" => request_body,
        "responses" => summarize_responses(op["responses"] || {})
      }
    end

    def resolve_type(schema, spec)
      return "string" unless schema.is_a?(Hash)

      if schema["$ref"]
        ref_schema = resolve_ref(schema["$ref"], spec)
        return ref_schema["type"] || "object" if ref_schema
      end

      schema["type"] || "string"
    end

    def resolve_schema(schema, spec)
      return nil unless schema.is_a?(Hash)

      if schema["$ref"]
        resolved = resolve_ref(schema["$ref"], spec)
        return resolved if resolved
      end

      # Inline schema — keep properties for LLM context
      result = { "type" => schema["type"] || "object" }
      if schema["properties"]
        result["properties"] = schema["properties"].transform_values do |v|
          { "type" => resolve_type(v, spec), "description" => v["description"] }.compact
        end
      end
      result["required"] = schema["required"] if schema["required"]
      result
    end

    def resolve_ref(ref, spec)
      parts = ref.gsub("#/", "").split("/")
      parts.reduce(spec) { |obj, key| obj.is_a?(Hash) ? obj[key] : nil }
    rescue StandardError
      nil
    end

    def summarize_responses(responses)
      responses.transform_values do |resp|
        { "description" => resp["description"] }.compact
      end
    end
  end
end
