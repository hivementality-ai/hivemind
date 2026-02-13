# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::HttpRequestExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock Process.clock_gettime for duration calculation
    allow(Process).to receive(:clock_gettime).and_return(0.0, 0.1) # 100ms duration
  end

  describe '#call' do
    context 'with list_apis action' do
      let(:input) { { "action" => "list_apis" } }

      before do
        create(:api_integration, 
          name: 'GitHub API', 
          base_url: 'https://api.github.com', 
          description: 'GitHub REST API',
          enabled: true,
          auth_type: 'bearer',
          endpoints: [
            { 'method' => 'GET', 'path' => '/user', 'summary' => 'Get current user' }
          ]
        )
        create(:api_integration, 
          name: 'Slack API', 
          base_url: 'https://slack.com/api', 
          description: 'Slack Web API',
          enabled: false, # disabled - should not appear
          auth_type: 'oauth'
        )
      end

      it 'lists enabled API integrations' do
        result = executor.call
        expect(result).to be_success
        
        apis = JSON.parse(result.data[:output])
        expect(apis.size).to eq(1)
        expect(apis.first).to include(
          'name' => 'GitHub API',
          'base_url' => 'https://api.github.com',
          'description' => 'GitHub REST API',
          'endpoints_count' => 1,
          'auth_type' => 'bearer'
        )
      end

      context 'with no APIs configured' do
        it 'returns empty array' do
          result = executor.call
          expect(result).to be_success
          apis = JSON.parse(result.data[:output])
          expect(apis).to eq([])
        end
      end
    end

    context 'with list_endpoints action' do
      let(:input) { { "action" => "list_endpoints", "integration" => "GitHub API" } }

      before do
        create(:api_integration,
          name: 'GitHub API',
          base_url: 'https://api.github.com',
          description: 'GitHub REST API',
          enabled: true,
          endpoints: [
            {
              'method' => 'GET',
              'path' => '/user',
              'summary' => 'Get authenticated user',
              'parameters' => [
                { 'name' => 'fields', 'in' => 'query', 'required' => false }
              ]
            },
            {
              'method' => 'POST',
              'path' => '/repos',
              'summary' => 'Create repository',
              'request_body' => {
                'content_type' => 'application/json',
                'required' => true
              },
              'parameters' => [
                { 'name' => 'name', 'in' => 'body', 'required' => true }
              ]
            }
          ]
        )
      end

      it 'lists API endpoints with details' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("API: GitHub API (https://api.github.com)")
        expect(result.data[:output]).to include("GitHub REST API")
        expect(result.data[:output]).to include("GET /user — Get authenticated user")
        expect(result.data[:output]).to include("Params: fields (query)")
        expect(result.data[:output]).to include("POST /repos — Create repository")
        expect(result.data[:output]).to include("Body: application/json (required)")
        expect(result.data[:output]).to include("Params: name* (body)")
      end

      context 'without integration name' do
        let(:input) { { "action" => "list_endpoints" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Specify 'integration' name")
        end
      end

      context 'with non-existent integration' do
        let(:input) { { "action" => "list_endpoints", "integration" => "Invalid API" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("API 'Invalid API' not found")
        end
      end
    end

    context 'with request action - raw request' do
      let(:input) do
        {
          "action" => "request",
          "method" => "GET",
          "url" => "https://api.example.com/users",
          "headers" => { "Authorization" => "Bearer token123" },
          "query" => { "page" => "1", "limit" => "10" }
        }
      end

      before do
        mock_successful_http_request
      end

      it 'executes HTTP request successfully' do
        result = executor.call
        expect(result).to be_success
        
        response = JSON.parse(result.data[:output])
        expect(response['status']).to eq(200)
        expect(response['method']).to eq('GET')
        expect(response['url']).to include('page=1')
        expect(response['url']).to include('limit=10')
        expect(response['body']).to eq({ 'users' => [{ 'id' => 1, 'name' => 'John' }] })
        expect(response['duration_ms']).to eq(100)
      end

      it 'configures HTTP client correctly' do
        executor.call
        expect(Net::HTTP).to have_received(:new).with('api.example.com', 443)
        expect(@mock_http).to have_received(:use_ssl=).with(true)
        expect(@mock_http).to have_received(:open_timeout=).with(30)
        expect(@mock_http).to have_received(:read_timeout=).with(30)
      end

      it 'sets request headers correctly' do
        executor.call
        expect(@mock_request).to have_received(:[]=).with("Authorization", "Bearer token123")
        expect(@mock_request).to have_received(:[]=).with("Accept", "application/json")
      end

      context 'with POST request and JSON body' do
        let(:input) do
          {
            "method" => "POST",
            "url" => "https://api.example.com/users",
            "body" => { "name" => "New User", "email" => "user@example.com" }
          }
        end

        before do
          mock_successful_http_request(method: Net::HTTP::Post)
        end

        it 'sends JSON body correctly' do
          executor.call
          expect(@mock_request).to have_received(:body=).with('{"name":"New User","email":"user@example.com"}')
          expect(@mock_request).to have_received(:[]=).with("Content-Type", "application/json")
        end
      end

      context 'with string body' do
        let(:input) do
          {
            "method" => "POST",
            "url" => "https://api.example.com/webhook",
            "body" => "raw string payload",
            "headers" => { "Content-Type" => "text/plain" }
          }
        end

        before do
          mock_successful_http_request(method: Net::HTTP::Post)
        end

        it 'sends string body directly' do
          executor.call
          expect(@mock_request).to have_received(:body=).with("raw string payload")
          expect(@mock_request).to have_received(:[]=).with("Content-Type", "text/plain")
        end
      end

      context 'without URL' do
        let(:input) { { "method" => "GET" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("URL is required for raw requests")
        end
      end

      context 'with invalid method' do
        let(:input) { { "method" => "INVALID", "url" => "https://example.com" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Invalid method: INVALID")
        end
      end

      context 'with private IP in production' do
        let(:input) { { "method" => "GET", "url" => "http://192.168.1.1/api" } }

        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it 'blocks private IP requests in production' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Requests to private IPs are not allowed")
        end
      end

      context 'with private IP in development' do
        let(:input) { { "method" => "GET", "url" => "http://192.168.1.1/api" } }

        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
          mock_successful_http_request(host: '192.168.1.1', port: 80, ssl: false)
        end

        it 'allows private IP requests in development' do
          result = executor.call
          expect(result).to be_success
        end
      end

      context 'with custom timeout' do
        let(:input) { { "method" => "GET", "url" => "https://example.com", "timeout" => 60 } }

        before do
          mock_successful_http_request
        end

        it 'uses custom timeout' do
          executor.call
          expect(@mock_http).to have_received(:read_timeout=).with(60)
        end
      end

      context 'with very high timeout' do
        let(:input) { { "method" => "GET", "url" => "https://example.com", "timeout" => 300 } }

        before do
          mock_successful_http_request
        end

        it 'caps timeout at 120 seconds' do
          executor.call
          expect(@mock_http).to have_received(:read_timeout=).with(120)
        end
      end
    end

    context 'with request action - integration request' do
      let(:input) do
        {
          "action" => "request",
          "integration" => "GitHub API",
          "method" => "GET",
          "path" => "/user",
          "query" => { "fields" => "login,name" }
        }
      end

      before do
        @api = create(:api_integration,
          name: 'GitHub API',
          base_url: 'https://api.github.com',
          enabled: true,
          auth_type: 'bearer',
          config: { 'api_key' => 'github_token_123' },
          timeout_seconds: 45,
          max_response_bytes: 500_000,
          endpoints: [
            { 'method' => 'GET', 'path' => '/user', 'summary' => 'Get user' }
          ]
        )
        
        # Mock API integration's request_headers method
        allow(@api).to receive(:request_headers).and_return({ 'Authorization' => 'Bearer github_token_123' })
        allow(ApiIntegration).to receive_message_chain(:enabled, :find_by).and_return(@api)
        allow(@api).to receive(:find_endpoint).and_return({ 'method' => 'GET', 'path' => '/user' })
        
        mock_successful_http_request
      end

      it 'executes integration request successfully' do
        result = executor.call
        expect(result).to be_success
        
        response = JSON.parse(result.data[:output])
        expect(response['status']).to eq(200)
        expect(response['url']).to eq('https://api.github.com/user?fields=login%2Cname')
      end

      it 'uses integration timeout and limits' do
        executor.call
        expect(@mock_http).to have_received(:read_timeout=).with(45)
      end

      context 'with non-existent integration' do
        let(:input) { { "integration" => "Invalid API", "path" => "/test" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("API 'Invalid API' not found")
        end
      end

      context 'with operation_id lookup' do
        let(:input) do
          {
            "integration" => "GitHub API",
            "operation_id" => "getCurrentUser"
          }
        end

        before do
          allow(@api).to receive(:find_endpoint)
            .with(operation_id: "getCurrentUser")
            .and_return({ 'method' => 'GET', 'path' => '/user' })
        end

        it 'finds endpoint by operation_id' do
          result = executor.call
          expect(result).to be_success
          expect(@api).to have_received(:find_endpoint).with(operation_id: "getCurrentUser")
        end
      end

      context 'with path parameters' do
        let(:input) do
          {
            "integration" => "GitHub API",
            "path" => "/repos/{owner}/{repo}",
            "query" => { "owner" => "octocat", "repo" => "Hello-World" }
          }
        end

        it 'interpolates path parameters' do
          result = executor.call
          expect(result).to be_success
          
          response = JSON.parse(result.data[:output])
          expect(response['url']).to eq('https://api.github.com/repos/octocat/Hello-World')
        end
      end

      context 'without path and endpoint not found' do
        let(:input) { { "integration" => "GitHub API", "method" => "GET" } }

        before do
          allow(@api).to receive(:find_endpoint).and_return(nil)
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No path specified and endpoint not found")
        end
      end
    end

    context 'with HTTP errors' do
      let(:input) { { "method" => "GET", "url" => "https://api.example.com/test" } }

      context 'when request times out' do
        before do
          @mock_http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(@mock_http)
          allow(@mock_http).to receive(:use_ssl=)
          allow(@mock_http).to receive(:open_timeout=)
          allow(@mock_http).to receive(:read_timeout=)
          allow(@mock_http).to receive(:request).and_raise(Net::ReadTimeout.new("Request timeout"))
        end

        it 'returns timeout error' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Request timed out after 30s")
        end
      end

      context 'when connection fails' do
        before do
          @mock_http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:new).and_return(@mock_http)
          allow(@mock_http).to receive(:use_ssl=)
          allow(@mock_http).to receive(:open_timeout=)
          allow(@mock_http).to receive(:read_timeout=)
          allow(@mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED.new("Connection refused"))
        end

        it 'returns connection error' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Connection failed: Connection refused")
        end
      end
    end

    context 'with large response' do
      let(:input) { { "method" => "GET", "url" => "https://api.example.com/large" } }
      let(:large_body) { 'x' * 2_000_000 } # 2MB response

      before do
        response = instance_double(Net::HTTPOK, code: '200', body: large_body)
        response.define_singleton_method(:each_header) { { 'content-type' => 'application/json' }.each }
        
        @mock_http = instance_double(Net::HTTP)
        @mock_request = instance_double(Net::HTTP::Get)
        
        allow(Net::HTTP).to receive(:new).and_return(@mock_http)
        allow(@mock_http).to receive(:use_ssl=)
        allow(@mock_http).to receive(:open_timeout=)
        allow(@mock_http).to receive(:read_timeout=)
        allow(@mock_http).to receive(:request).and_return(response)
        
        allow(Net::HTTP::Get).to receive(:new).and_return(@mock_request)
        allow(@mock_request).to receive(:[]=)
      end

      it 'truncates large responses' do
        result = executor.call
        expect(result).to be_success
        
        response_data = JSON.parse(result.data[:output])
        expect(response_data['truncated']).to be true
        expect(response_data['body'].length).to be <= Tools::HttpRequestExecutor::MAX_RESPONSE_SIZE
      end
    end

    context 'with non-JSON response' do
      let(:input) { { "method" => "GET", "url" => "https://example.com/html" } }

      before do
        mock_successful_http_request(body: '<html><body>Hello World</body></html>')
      end

      it 'returns raw body when JSON parsing fails' do
        result = executor.call
        expect(result).to be_success
        
        response = JSON.parse(result.data[:output])
        expect(response['body']).to eq('<html><body>Hello World</body></html>')
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("request, list_apis, list_endpoints")
      end
    end

    context 'when general error occurs' do
      let(:input) { { "action" => "request", "url" => "https://example.com" } }

      before do
        allow(URI).to receive(:parse).and_raise(StandardError.new("Invalid URI"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("HTTP request failed: Invalid URI")
      end
    end
  end

  describe '#private_ip?' do
    it 'detects private IP addresses' do
      expect(executor.send(:private_ip?, 'http://192.168.1.1')).to be true
      expect(executor.send(:private_ip?, 'http://10.0.0.1')).to be true
      expect(executor.send(:private_ip?, 'http://172.16.0.1')).to be true
      expect(executor.send(:private_ip?, 'http://127.0.0.1')).to be true
      expect(executor.send(:private_ip?, 'http://169.254.1.1')).to be true
    end

    it 'allows public IP addresses' do
      expect(executor.send(:private_ip?, 'https://8.8.8.8')).to be false
      expect(executor.send(:private_ip?, 'https://google.com')).to be false
      expect(executor.send(:private_ip?, 'https://1.1.1.1')).to be false
    end

    it 'handles invalid URLs gracefully' do
      expect(executor.send(:private_ip?, 'invalid-url')).to be false
      expect(executor.send(:private_ip?, 'http://')).to be false
    end
  end

  describe '#try_parse_json' do
    it 'parses valid JSON' do
      result = executor.send(:try_parse_json, '{"key": "value"}')
      expect(result).to eq({ 'key' => 'value' })
    end

    it 'returns truncated string for invalid JSON' do
      long_string = 'not json ' * 2000
      result = executor.send(:try_parse_json, long_string)
      expect(result).to be_a(String)
      expect(result.length).to be <= 10_000
    end
  end

  private

  def mock_successful_http_request(method: Net::HTTP::Get, host: 'api.example.com', port: 443, ssl: true, body: nil)
    body ||= JSON.generate({ 'users' => [{ 'id' => 1, 'name' => 'John' }] })
    
    response = instance_double(Net::HTTPOK, code: '200', body: body)
    response.define_singleton_method(:each_header) do
      { 'content-type' => 'application/json', 'server' => 'nginx' }.each
    end
    
    @mock_http = instance_double(Net::HTTP)
    @mock_request = instance_double(method)
    
    allow(Net::HTTP).to receive(:new).with(host, port).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=).with(ssl)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)
    
    allow(method).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:body=) if [Net::HTTP::Post, Net::HTTP::Put, Net::HTTP::Patch].include?(method)
  end
end