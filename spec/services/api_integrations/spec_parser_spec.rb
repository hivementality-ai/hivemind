# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiIntegrations::SpecParser do
  describe '.call' do
    describe 'OpenAPI 3.x parsing' do
      let(:openapi_spec) do
        {
          "openapi" => "3.0.1",
          "info" => {
            "title" => "Pet Store API",
            "description" => "A sample API for managing pets",
            "version" => "1.0.0"
          },
          "servers" => [
            { "url" => "https://api.petstore.com/v1" }
          ],
          "paths" => {
            "/pets" => {
              "get" => {
                "operationId" => "listPets",
                "summary" => "List all pets",
                "description" => "Returns a list of pets",
                "parameters" => [
                  {
                    "name" => "limit",
                    "in" => "query",
                    "required" => false,
                    "schema" => { "type" => "integer" },
                    "description" => "How many items to return"
                  }
                ],
                "responses" => {
                  "200" => {
                    "description" => "A list of pets"
                  }
                }
              },
              "post" => {
                "operationId" => "createPet",
                "summary" => "Create a pet",
                "requestBody" => {
                  "required" => true,
                  "content" => {
                    "application/json" => {
                      "schema" => {
                        "type" => "object",
                        "properties" => {
                          "name" => { "type" => "string", "description" => "Pet name" },
                          "age" => { "type" => "integer" }
                        },
                        "required" => ["name"]
                      }
                    }
                  }
                },
                "responses" => {
                  "201" => { "description" => "Pet created" }
                }
              }
            }
          }
        }
      end

      it 'successfully parses OpenAPI 3.x spec' do
        result = described_class.call(spec_input: openapi_spec)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true

        data = result.data
        expect(data[:title]).to eq("Pet Store API")
        expect(data[:description]).to eq("A sample API for managing pets")
        expect(data[:base_url]).to eq("https://api.petstore.com/v1")
        expect(data[:spec_format]).to eq("openapi")
        expect(data[:spec_data]).to eq(openapi_spec)
        expect(data[:endpoints]).to be_an(Array)
      end

      it 'correctly parses GET endpoint' do
        result = described_class.call(spec_input: openapi_spec)
        endpoints = result.data[:endpoints]

        get_endpoint = endpoints.find { |ep| ep["method"] == "get" }
        expect(get_endpoint).to be_present
        expect(get_endpoint["path"]).to eq("/pets")
        expect(get_endpoint["operation_id"]).to eq("listPets")
        expect(get_endpoint["summary"]).to eq("List all pets")
        expect(get_endpoint["description"]).to eq("Returns a list of pets")

        # Check parameters
        params = get_endpoint["parameters"]
        expect(params).to be_an(Array)
        expect(params.first).to include(
          "name" => "limit",
          "in" => "query",
          "required" => false,
          "type" => "integer",
          "description" => "How many items to return"
        )

        # Check responses
        responses = get_endpoint["responses"]
        expect(responses["200"]).to eq({ "description" => "A list of pets" })
      end

      it 'correctly parses POST endpoint with request body' do
        result = described_class.call(spec_input: openapi_spec)
        endpoints = result.data[:endpoints]

        post_endpoint = endpoints.find { |ep| ep["method"] == "post" }
        expect(post_endpoint).to be_present
        expect(post_endpoint["operation_id"]).to eq("createPet")

        # Check request body
        request_body = post_endpoint["request_body"]
        expect(request_body["required"]).to be true
        expect(request_body["content_type"]).to eq("application/json")

        schema = request_body["schema"]
        expect(schema["type"]).to eq("object")
        expect(schema["properties"]["name"]["type"]).to eq("string")
        expect(schema["properties"]["name"]["description"]).to eq("Pet name")
        expect(schema["properties"]["age"]["type"]).to eq("integer")
        expect(schema["required"]).to eq(["name"])
      end
    end

    describe 'Swagger 2.x parsing' do
      let(:swagger_spec) do
        {
          "swagger" => "2.0",
          "info" => {
            "title" => "Legacy API",
            "description" => "An older API format"
          },
          "host" => "api.legacy.com",
          "basePath" => "/v2",
          "schemes" => ["https"],
          "paths" => {
            "/users" => {
              "get" => {
                "operationId" => "getUsers",
                "summary" => "Get users",
                "parameters" => [
                  {
                    "name" => "page",
                    "in" => "query",
                    "type" => "integer"
                  }
                ],
                "responses" => {
                  "200" => { "description" => "Success" }
                }
              }
            }
          }
        }
      end

      it 'successfully parses Swagger 2.x spec' do
        result = described_class.call(spec_input: swagger_spec)

        expect(result.success?).to be true

        data = result.data
        expect(data[:title]).to eq("Legacy API")
        expect(data[:base_url]).to eq("https://api.legacy.com/v2")
        expect(data[:spec_format]).to eq("swagger")
        expect(data[:endpoints].length).to eq(1)
      end

      it 'correctly constructs base URL from host, basePath, and schemes' do
        result = described_class.call(spec_input: swagger_spec)
        
        expect(result.data[:base_url]).to eq("https://api.legacy.com/v2")
      end

      it 'defaults to https scheme when not specified' do
        spec_without_schemes = swagger_spec.dup.tap { |s| s.delete("schemes") }
        result = described_class.call(spec_input: spec_without_schemes)
        
        expect(result.data[:base_url]).to eq("https://api.legacy.com/v2")
      end
    end

    describe 'generic/custom spec parsing' do
      let(:custom_spec) do
        {
          "title" => "Custom API",
          "description" => "A custom API format",
          "base_url" => "https://custom.api.com",
          "endpoints" => [
            {
              "path" => "/custom",
              "method" => "GET",
              "name" => "getCustom",
              "description" => "Get custom data",
              "parameters" => [
                { "name" => "filter", "type" => "string" }
              ]
            }
          ]
        }
      end

      it 'successfully parses custom spec format' do
        result = described_class.call(spec_input: custom_spec)

        expect(result.success?).to be true

        data = result.data
        expect(data[:title]).to eq("Custom API")
        expect(data[:base_url]).to eq("https://custom.api.com")
        expect(data[:spec_format]).to eq("custom")

        endpoint = data[:endpoints].first
        expect(endpoint["path"]).to eq("/custom")
        expect(endpoint["method"]).to eq("get") # Should be normalized to lowercase
        expect(endpoint["operation_id"]).to eq("getCustom")
        expect(endpoint["summary"]).to eq("Get custom data")
      end

      it 'handles missing endpoints array' do
        spec_without_endpoints = { "title" => "Empty API" }
        result = described_class.call(spec_input: spec_without_endpoints)

        expect(result.success?).to be true
        expect(result.data[:endpoints]).to eq([])
      end
    end

    describe 'input format handling' do
      let(:simple_spec) do
        {
          "openapi" => "3.0.0",
          "info" => { "title" => "Test API" },
          "paths" => {}
        }
      end

      context 'when input is a Hash' do
        it 'parses directly' do
          result = described_class.call(spec_input: simple_spec)
          expect(result.success?).to be true
        end
      end

      context 'when input is JSON string' do
        it 'parses JSON string' do
          json_string = simple_spec.to_json
          result = described_class.call(spec_input: json_string)
          
          expect(result.success?).to be true
          expect(result.data[:title]).to eq("Test API")
        end
      end

      context 'when input is YAML string' do
        it 'parses YAML string' do
          yaml_string = simple_spec.to_yaml
          result = described_class.call(spec_input: yaml_string)
          
          expect(result.success?).to be true
          expect(result.data[:title]).to eq("Test API")
        end
      end
    end

    describe 'schema reference resolution' do
      let(:spec_with_refs) do
        {
          "openapi" => "3.0.0",
          "info" => { "title" => "API with Refs" },
          "components" => {
            "schemas" => {
              "Pet" => {
                "type" => "object",
                "properties" => {
                  "name" => { "type" => "string" }
                }
              }
            }
          },
          "paths" => {
            "/pets" => {
              "post" => {
                "requestBody" => {
                  "content" => {
                    "application/json" => {
                      "schema" => { "$ref" => "#/components/schemas/Pet" }
                    }
                  }
                },
                "responses" => { "200" => { "description" => "OK" } }
              }
            }
          }
        }
      end

      it 'resolves $ref references' do
        result = described_class.call(spec_input: spec_with_refs)

        endpoint = result.data[:endpoints].first
        schema = endpoint["request_body"]["schema"]
        
        expect(schema["type"]).to eq("object")
        expect(schema["properties"]["name"]["type"]).to eq("string")
      end
    end

    describe 'error handling' do
      context 'with invalid JSON' do
        it 'returns failure for malformed JSON' do
          result = described_class.call(spec_input: '{ invalid json }')
          
          expect(result.success?).to be false
          expect(result.error).to include("Spec parse error")
        end
      end

      context 'with invalid YAML' do
        it 'returns failure for malformed YAML that is also not JSON' do
          result = described_class.call(spec_input: "invalid:\n\tyaml\n  - structure")
          
          expect(result.success?).to be false
          expect(result.error).to include("Spec parse error")
        end
      end

      context 'with unsupported input type' do
        it 'returns failure for non-string non-hash input' do
          result = described_class.call(spec_input: 123)
          
          expect(result.success?).to be false
          expect(result.error).to eq("Could not parse spec")
        end
      end

      context 'when parsing raises an exception' do
        before do
          allow(JSON).to receive(:parse).and_raise(StandardError, "Unexpected error")
          allow(YAML).to receive(:safe_load).and_raise(StandardError, "YAML error")
        end

        it 'catches exceptions and returns failure' do
          result = described_class.call(spec_input: "some input")
          
          expect(result.success?).to be false
          expect(result.error).to include("Spec parse error")
        end
      end
    end

    describe 'edge cases' do
      context 'with empty paths' do
        let(:empty_paths_spec) do
          {
            "openapi" => "3.0.0",
            "info" => { "title" => "Empty API" },
            "paths" => {}
          }
        end

        it 'handles specs with no paths' do
          result = described_class.call(spec_input: empty_paths_spec)
          
          expect(result.success?).to be true
          expect(result.data[:endpoints]).to eq([])
        end
      end

      context 'with missing info section' do
        let(:no_info_spec) do
          {
            "openapi" => "3.0.0",
            "paths" => {}
          }
        end

        it 'handles specs with missing info' do
          result = described_class.call(spec_input: no_info_spec)
          
          expect(result.success?).to be true
          expect(result.data[:title]).to be_nil
          expect(result.data[:description]).to be_nil
        end
      end

      context 'with HTTP methods in different cases' do
        let(:mixed_case_spec) do
          {
            "openapi" => "3.0.0",
            "info" => { "title" => "Case Test" },
            "paths" => {
              "/test" => {
                "GET" => { "responses" => { "200" => { "description" => "OK" } } },
                "Post" => { "responses" => { "201" => { "description" => "Created" } } }
              }
            }
          }
        end

        it 'only processes lowercase HTTP methods' do
          result = described_class.call(spec_input: mixed_case_spec)
          
          methods = result.data[:endpoints].map { |ep| ep["method"] }
          expect(methods).to eq(["post"]) # Only finds lowercase/standard methods
        end
      end
    end
  end
end