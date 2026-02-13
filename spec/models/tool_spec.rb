# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tool, type: :model do
  describe 'associations' do
    it { should have_many(:tool_executions).dependent(:destroy) }
    it { should have_many(:agent_tools).dependent(:destroy) }
    it { should have_many(:agents).through(:agent_tools) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    
    describe 'uniqueness of name' do
      let!(:existing_tool) { create(:tool, name: 'unique_tool') }
      
      it 'rejects duplicate names' do
        new_tool = build(:tool, name: 'unique_tool')
        expect(new_tool).not_to be_valid
        expect(new_tool.errors[:name]).to include('has already been taken')
      end
    end
    
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:executor_type) }

    it 'validates executor_type inclusion' do
      valid_types = %w[shell file_read file_write file_edit web_search web_fetch http_request browser
                       memory_search image cron message heartbeat_write delegate spawn spawn_status]
      tool = build(:tool, executor_type: 'shell')
      expect(tool).to be_valid

      tool = build(:tool, executor_type: 'invalid_type')
      expect(tool).not_to be_valid
      expect(tool.errors[:executor_type]).to include('is not included in the list')
    end
  end

  describe 'scopes' do
    let!(:enabled_tool) { create(:tool, enabled: true) }
    let!(:disabled_tool) { create(:tool, enabled: false) }
    let!(:builtin_tool) { create(:tool, builtin: true, enabled: true) }

    describe '.enabled' do
      it 'returns only enabled tools' do
        expect(Tool.enabled).to include(enabled_tool, builtin_tool)
        expect(Tool.enabled).not_to include(disabled_tool)
      end
    end

    describe '.builtin' do
      it 'returns only builtin tools' do
        expect(Tool.builtin).to include(builtin_tool)
        expect(Tool.builtin).not_to include(enabled_tool, disabled_tool)
      end
    end
  end

  describe '#to_llm_tool' do
    let(:tool) do
      create(:tool,
             name: 'web_search',
             description: 'Search the web',
             parameters_schema: {
               properties: {
                 query: { type: 'string', description: 'Search query' },
                 num_results: { type: 'integer', description: 'Number of results' }
               },
               required: ['query']
             })
    end

    it 'returns a hash with name, description, and input_schema' do
      result = tool.to_llm_tool
      expect(result).to be_a(Hash)
      expect(result).to have_key(:name)
      expect(result).to have_key(:description)
      expect(result).to have_key(:input_schema)
    end

    it 'includes correct name and description' do
      result = tool.to_llm_tool
      expect(result[:name]).to eq('web_search')
      expect(result[:description]).to eq('Search the web')
    end

    it 'formats input_schema correctly' do
      result = tool.to_llm_tool
      schema = result[:input_schema]

      expect(schema[:type]).to eq('object')
      expect(schema[:properties].keys).to include('query', 'num_results')
      expect(schema[:required]).to eq(['query'])
    end

    context 'with empty parameters_schema' do
      let(:tool_no_params) do
        create(:tool, parameters_schema: {})
      end

      it 'returns empty properties and required' do
        result = tool_no_params.to_llm_tool
        schema = result[:input_schema]

        expect(schema[:properties]).to eq({})
        expect(schema[:required]).to eq([])
      end
    end

    context 'with empty parameters_schema properties' do
      let(:tool_empty_params) do
        create(:tool, parameters_schema: {
          properties: {},
          required: []
        })
      end

      it 'handles gracefully' do
        result = tool_empty_params.to_llm_tool
        schema = result[:input_schema]

        expect(schema[:properties]).to eq({})
        expect(schema[:required]).to eq([])
      end
    end
  end

  describe 'factory' do
    it 'creates a valid tool' do
      expect(build(:tool)).to be_valid
    end

    it 'creates valid tools with traits' do
      expect(build(:tool, :shell_tool)).to be_valid
      expect(build(:tool, :file_read_tool)).to be_valid
      expect(build(:tool, :file_write_tool)).to be_valid
      expect(build(:tool, :web_search_tool)).to be_valid
      expect(build(:tool, :browser_tool)).to be_valid
      expect(build(:tool, :image_tool)).to be_valid
      expect(build(:tool, :cron_tool)).to be_valid
      expect(build(:tool, :disabled)).to be_valid
      expect(build(:tool, :builtin)).to be_valid
    end
  end

  describe 'executor_type values' do
    let(:valid_executor_types) do
      %w[shell file_read file_write file_edit web_search web_fetch http_request browser
         memory_search image cron message heartbeat_write delegate spawn spawn_status]
    end

    it 'accepts all valid executor types' do
      valid_executor_types.each do |executor_type|
        tool = build(:tool, executor_type: executor_type)
        expect(tool).to be_valid, "#{executor_type} should be valid"
      end
    end

    it 'rejects invalid executor types' do
      tool = build(:tool, executor_type: 'invalid_executor')
      expect(tool).not_to be_valid
      expect(tool.errors[:executor_type]).to be_present
    end
  end
end
