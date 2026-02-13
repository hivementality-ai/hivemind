# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::JiraExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock Jira credentials
    allow(executor).to receive(:base_url).and_return('https://company.atlassian.net')
    allow(executor).to receive(:jira_email).and_return('user@company.com')
    allow(executor).to receive(:jira_token).and_return('jira-token-123')

    # Mock HTTP client
    @mock_http = instance_double(Net::HTTP)
    @mock_request = instance_double(Net::HTTP::Get)
    allow(Net::HTTP).to receive(:new).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
  end

  describe '#call' do
    context 'with get_issue action' do
      let(:input) { { "action" => "get_issue", "key" => "PROJ-123" } }

      before do
        mock_successful_jira_response(mock_issue_response)
      end

      it 'retrieves issue successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("PROJ-123: Fix critical bug")
        expect(result.data[:output]).to include("Type: Bug | Status: In Progress | Priority: High")
        expect(result.data[:output]).to include("Assignee: John Doe | Reporter: Jane Smith")
        expect(result.data[:output]).to include("This is a critical bug that needs fixing")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'makes correct API request' do
        executor.call
        expect(Net::HTTP).to have_received(:new).with('company.atlassian.net', 443)
        expect(@mock_request).to have_received(:[]=).with("Authorization", "Basic #{Base64.strict_encode64("user@company.com:jira-token-123")}")
        expect(@mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      end

      context 'without issue key' do
        let(:input) { { "action" => "get_issue" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No issue key provided")
        end
      end

      context 'with issue having subtasks' do
        before do
          response = mock_issue_response
          response["fields"]["subtasks"] = [
            { "key" => "PROJ-124", "fields" => { "summary" => "Subtask 1" } },
            { "key" => "PROJ-125", "fields" => { "summary" => "Subtask 2" } }
          ]
          mock_successful_jira_response(response)
        end

        it 'includes subtasks in output' do
          result = executor.call
          expect(result.data[:output]).to include("Subtasks: PROJ-124: Subtask 1, PROJ-125: Subtask 2")
        end
      end
    end

    context 'with search action' do
      let(:input) { { "action" => "search", "jql" => "project = PROJ AND status != Done" } }

      before do
        mock_successful_jira_response({
          "total" => 25,
          "issues" => [
            {
              "key" => "PROJ-123",
              "fields" => {
                "summary" => "Fix critical bug",
                "status" => { "name" => "In Progress" },
                "assignee" => { "displayName" => "John Doe" },
                "priority" => { "name" => "High" }
              }
            },
            {
              "key" => "PROJ-124",
              "fields" => {
                "summary" => "Add new feature",
                "status" => { "name" => "To Do" },
                "assignee" => nil,
                "priority" => { "name" => "Medium" }
              }
            }
          ]
        })
      end

      it 'searches issues successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Search: project = PROJ AND status != Done")
        expect(result.data[:output]).to include("Found: 25 (showing 2)")
        expect(result.data[:output]).to include("PROJ-123 [In Progress] Fix critical bug (John Doe)")
        expect(result.data[:output]).to include("PROJ-124 [To Do] Add new feature (Unassigned)")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without JQL query' do
        let(:input) { { "action" => "search" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No JQL query provided")
        end
      end

      context 'with custom limit' do
        let(:input) { { "action" => "search", "jql" => "project = PROJ", "limit" => 5 } }

        it 'includes limit in API request' do
          executor.call
          expect(@mock_http).to have_received(:request) do |req|
            expect(req.uri.to_s).to include("maxResults=5")
          end
        end
      end
    end

    context 'with create_issue action' do
      let(:input) do
        {
          "action" => "create_issue",
          "project" => "PROJ",
          "summary" => "New issue summary",
          "issue_type" => "Bug",
          "description" => "This is the description",
          "priority" => "High",
          "labels" => "urgent,bug"
        }
      end

      before do
        mock_successful_jira_response({ "key" => "PROJ-126" })
      end

      it 'creates issue successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Created PROJ-126: New issue summary")
        expect(result.data[:output]).to include("URL: https://company.atlassian.net/browse/PROJ-126")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'sends correct request body' do
        executor.call
        expect(@mock_http).to have_received(:request) do |req|
          body = JSON.parse(req.body)
          expect(body["fields"]["project"]["key"]).to eq("PROJ")
          expect(body["fields"]["summary"]).to eq("New issue summary")
          expect(body["fields"]["issuetype"]["name"]).to eq("Bug")
          expect(body["fields"]["priority"]["name"]).to eq("High")
          expect(body["fields"]["labels"]).to eq(["urgent", "bug"])
          expect(body["fields"]["description"]["type"]).to eq("doc")
        end
      end

      context 'with minimum required fields' do
        let(:input) { { "action" => "create_issue", "project" => "PROJ", "summary" => "Simple issue" } }

        it 'defaults to Task issue type' do
          executor.call
          expect(@mock_http).to have_received(:request) do |req|
            body = JSON.parse(req.body)
            expect(body["fields"]["issuetype"]["name"]).to eq("Task")
          end
        end
      end

      context 'without required fields' do
        context 'without project' do
          let(:input) { { "action" => "create_issue", "summary" => "Test" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("project and summary required")
          end
        end

        context 'without summary' do
          let(:input) { { "action" => "create_issue", "project" => "PROJ" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("project and summary required")
          end
        end
      end
    end

    context 'with add_comment action' do
      let(:input) { { "action" => "add_comment", "key" => "PROJ-123", "body" => "This is a comment" } }

      before do
        mock_successful_jira_response({})
      end

      it 'adds comment successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Comment added to PROJ-123")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'sends comment in ADF format' do
        executor.call
        expect(@mock_http).to have_received(:request) do |req|
          body = JSON.parse(req.body)
          expect(body["body"]["type"]).to eq("doc")
          expect(body["body"]["content"].first["type"]).to eq("paragraph")
          expect(body["body"]["content"].first["content"].first["text"]).to eq("This is a comment")
        end
      end

      context 'without required fields' do
        let(:input) { { "action" => "add_comment", "key" => "PROJ-123" } }

        it 'returns failure when body missing' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("key and body required")
        end
      end
    end

    context 'with list_comments action' do
      let(:input) { { "action" => "list_comments", "key" => "PROJ-123" } }

      before do
        mock_successful_jira_response({
          "comments" => [
            {
              "author" => { "displayName" => "John Doe" },
              "created" => "2023-01-15T10:30:00.000+0000",
              "body" => {
                "type" => "doc",
                "content" => [
                  {
                    "type" => "paragraph",
                    "content" => [{ "type" => "text", "text" => "First comment" }]
                  }
                ]
              }
            },
            {
              "author" => { "displayName" => "Jane Smith" },
              "created" => "2023-01-16T14:20:00.000+0000",
              "body" => {
                "type" => "doc",
                "content" => [
                  {
                    "type" => "paragraph",
                    "content" => [{ "type" => "text", "text" => "Second comment" }]
                  }
                ]
              }
            }
          ]
        })
      end

      it 'lists comments successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Comments on PROJ-123 (2):")
        expect(result.data[:output]).to include("2023-01-15 — John Doe: First comment")
        expect(result.data[:output]).to include("2023-01-16 — Jane Smith: Second comment")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with transition action' do
      let(:input) { { "action" => "transition", "key" => "PROJ-123", "transition" => "Done" } }

      before do
        # First call to get transitions
        allow(@mock_http).to receive(:request).and_return(
          mock_response({
            "transitions" => [
              { "id" => "11", "name" => "To Do" },
              { "id" => "21", "name" => "In Progress" },
              { "id" => "31", "name" => "Done" }
            ]
          }),
          mock_response({}) # Second call to perform transition
        )
      end

      it 'transitions issue successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("PROJ-123 transitioned to: Done")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'with invalid transition' do
        before do
          allow(@mock_http).to receive(:request).and_return(
            mock_response({
              "transitions" => [
                { "id" => "11", "name" => "To Do" }
              ]
            })
          )
        end

        it 'returns failure for unavailable transition' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Transition 'Done' not available")
          expect(result.error).to include("Use list_transitions")
        end
      end
    end

    context 'with list_transitions action' do
      let(:input) { { "action" => "list_transitions", "key" => "PROJ-123" } }

      before do
        mock_successful_jira_response({
          "transitions" => [
            { "id" => "11", "name" => "To Do" },
            { "id" => "21", "name" => "In Progress" },
            { "id" => "31", "name" => "Done" }
          ]
        })
      end

      it 'lists available transitions' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Available transitions for PROJ-123:")
        expect(result.data[:output]).to include("11: To Do")
        expect(result.data[:output]).to include("21: In Progress")
        expect(result.data[:output]).to include("31: Done")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with assign action' do
      let(:input) { { "action" => "assign", "key" => "PROJ-123", "assignee_id" => "user123" } }

      before do
        mock_successful_jira_response({})
      end

      it 'assigns issue successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("PROJ-123 assigned to user123")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'without required fields' do
        let(:input) { { "action" => "assign", "key" => "PROJ-123" } }

        it 'returns failure when assignee_id missing' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("key and assignee_id required")
        end
      end
    end

    context 'with list_projects action' do
      let(:input) { { "action" => "list_projects" } }

      before do
        mock_successful_jira_response([
          { "key" => "PROJ", "name" => "Main Project" },
          { "key" => "TEST", "name" => "Test Project" }
        ])
      end

      it 'lists projects successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Projects:")
        expect(result.data[:output]).to include("PROJ: Main Project")
        expect(result.data[:output]).to include("TEST: Test Project")
        expect(result.data[:exit_code]).to eq(0)
      end
    end

    context 'with my_issues action' do
      let(:input) { { "action" => "my_issues" } }

      before do
        mock_successful_jira_response({
          "total" => 3,
          "issues" => [
            {
              "key" => "PROJ-123",
              "fields" => {
                "summary" => "My first issue",
                "status" => { "name" => "In Progress" },
                "assignee" => { "displayName" => "Me" }
              }
            },
            {
              "key" => "PROJ-124",
              "fields" => {
                "summary" => "My second issue",
                "status" => { "name" => "To Do" },
                "assignee" => { "displayName" => "Me" }
              }
            }
          ]
        })
      end

      it 'lists my issues successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("My open issues (3 total, showing 2):")
        expect(result.data[:output]).to include("PROJ-123 [In Progress] My first issue")
        expect(result.data[:output]).to include("PROJ-124 [To Do] My second issue")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'uses correct JQL query' do
        executor.call
        expect(@mock_http).to have_received(:request) do |req|
          expect(req.uri.to_s).to include(URI.encode_www_form_component("assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"))
        end
      end
    end

    context 'with update_issue action' do
      let(:input) do
        {
          "action" => "update_issue",
          "key" => "PROJ-123",
          "summary" => "Updated summary",
          "priority" => "Low"
        }
      end

      before do
        mock_successful_jira_response({})
      end

      it 'updates issue successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Updated PROJ-123")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'with no fields to update' do
        let(:input) { { "action" => "update_issue", "key" => "PROJ-123" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No fields to update")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("get_issue, search, create_issue")
      end
    end

    context 'when API request fails' do
      let(:input) { { "action" => "get_issue", "key" => "PROJ-123" } }

      before do
        response = instance_double(Net::HTTPBadRequest, is_a?: false, code: '400', body: '{"error":"Issue not found"}')
        allow(@mock_http).to receive(:request).and_return(response)
        allow(Net::HTTP::Get).to receive(:new).and_return(@mock_request)
        allow(@mock_request).to receive(:[]=)
      end

      it 'returns failure with API error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Jira error: HTTP 400")
      end
    end

    context 'when network error occurs' do
      let(:input) { { "action" => "get_issue", "key" => "PROJ-123" } }

      before do
        allow(@mock_http).to receive(:request).and_raise(SocketError.new("Network unreachable"))
        allow(Net::HTTP::Get).to receive(:new).and_return(@mock_request)
        allow(@mock_request).to receive(:[]=)
      end

      it 'returns failure with network error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Jira error: Network unreachable")
      end
    end
  end

  describe 'credential methods' do
    context 'with vault entries' do
      before do
        create(:vault_entry, namespace: 'jira', key: 'base_url', value: 'https://vault.atlassian.net')
        create(:vault_entry, namespace: 'jira', key: 'email', value: 'vault@company.com')
        create(:vault_entry, namespace: 'jira', key: 'api_token', value: 'vault-token-456')
        
        # Reset memoized values
        executor.remove_instance_variable(:@base_url) if executor.instance_variable_defined?(:@base_url)
        executor.remove_instance_variable(:@jira_email) if executor.instance_variable_defined?(:@jira_email)
        executor.remove_instance_variable(:@jira_token) if executor.instance_variable_defined?(:@jira_token)
      end

      it 'reads credentials from vault' do
        expect(executor.send(:base_url)).to eq('https://vault.atlassian.net')
        expect(executor.send(:jira_email)).to eq('vault@company.com')
        expect(executor.send(:jira_token)).to eq('vault-token-456')
      end
    end

    context 'with environment variables' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("JIRA_BASE_URL").and_return('https://env.atlassian.net')
        allow(ENV).to receive(:[]).with("JIRA_EMAIL").and_return('env@company.com')
        allow(ENV).to receive(:[]).with("JIRA_API_TOKEN").and_return('env-token-789')
      end

      it 'falls back to environment variables' do
        expect(executor.send(:base_url)).to eq('https://env.atlassian.net')
        expect(executor.send(:jira_email)).to eq('env@company.com')
        expect(executor.send(:jira_token)).to eq('env-token-789')
      end
    end
  end

  describe '#adf_paragraph' do
    it 'converts text to ADF format' do
      result = executor.send(:adf_paragraph, "First paragraph\n\nSecond paragraph")
      
      expect(result[:type]).to eq("doc")
      expect(result[:version]).to eq(1)
      expect(result[:content].size).to eq(2)
      expect(result[:content][0][:type]).to eq("paragraph")
      expect(result[:content][0][:content][0][:text]).to eq("First paragraph")
      expect(result[:content][1][:content][0][:text]).to eq("Second paragraph")
    end
  end

  describe '#extract_text' do
    it 'extracts text from ADF document' do
      adf = {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [{ "type" => "text", "text" => "Hello world" }]
          }
        ]
      }
      
      result = executor.send(:extract_text, adf)
      expect(result).to eq("Hello world")
    end

    it 'handles non-ADF input' do
      result = executor.send(:extract_text, "plain text")
      expect(result).to eq("")
    end
  end

  describe '#vault_get' do
    it 'retrieves vault entries' do
      create(:vault_entry, namespace: 'jira', key: 'test_key', value: 'test_value')
      result = executor.send(:vault_get, 'jira', 'test_key')
      expect(result).to eq('test_value')
    end

    it 'returns nil for non-existent entries' do
      result = executor.send(:vault_get, 'nonexistent', 'key')
      expect(result).to be_nil
    end
  end

  private

  def mock_issue_response
    {
      "key" => "PROJ-123",
      "fields" => {
        "summary" => "Fix critical bug",
        "status" => { "name" => "In Progress" },
        "priority" => { "name" => "High" },
        "issuetype" => { "name" => "Bug" },
        "assignee" => { "displayName" => "John Doe" },
        "reporter" => { "displayName" => "Jane Smith" },
        "created" => "2023-01-10T09:00:00.000+0000",
        "updated" => "2023-01-15T14:30:00.000+0000",
        "labels" => ["urgent", "critical"],
        "description" => {
          "type" => "doc",
          "content" => [
            {
              "type" => "paragraph",
              "content" => [{ "type" => "text", "text" => "This is a critical bug that needs fixing" }]
            }
          ]
        },
        "parent" => { "key" => "PROJ-100" },
        "subtasks" => []
      }
    }
  end

  def mock_successful_jira_response(response_data)
    response = mock_response(response_data)
    allow(@mock_http).to receive(:request).and_return(response)
    
    request_classes = [Net::HTTP::Get, Net::HTTP::Post, Net::HTTP::Put]
    request_classes.each do |klass|
      allow(klass).to receive(:new).and_return(@mock_request)
    end
    
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:body=)
    allow(@mock_request).to receive(:uri).and_return(URI('https://company.atlassian.net/rest/api/3/issue/PROJ-123'))
  end

  def mock_response(data)
    response = instance_double(Net::HTTPOK, is_a?: Net::HTTPSuccess, body: JSON.generate(data))
    allow(response).to receive(:is_a?).with(Net::HTTPNoContent).and_return(false)
    response
  end
end