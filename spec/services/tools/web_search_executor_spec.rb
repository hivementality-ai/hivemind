# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::WebSearchExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  describe '#call' do
    context 'with valid search query' do
      let(:input) { { query: 'ruby programming' } }

      before do
        allow(Faraday).to receive(:get).and_return(
          instance_double(Faraday::Response,
                         body: JSON.generate({
                           web: [
                             { title: 'Ruby Site', url: 'https://ruby-lang.org', body: 'Official Ruby' },
                             { title: 'Rails', url: 'https://rubyonrails.org', body: 'Web framework' }
                           ]
                         }),
                         success?: true)
        )
      end

      it 'returns success with search results' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include('Ruby')
      end
    end

    context 'without query parameter' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
      end
    end

    context 'with empty query' do
      let(:input) { { query: '' } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
      end
    end

    context 'when API call fails' do
      let(:input) { { query: 'test' } }

      before do
        allow(Faraday).to receive(:get).and_raise(StandardError.new('API error'))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include('API error')
      end
    end
  end
end
