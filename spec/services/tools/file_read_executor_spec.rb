# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::FileReadExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  describe '#call' do
    context 'with valid file path' do
      let(:temp_file) { Tempfile.new('test').tap { |f| f.write('test content'); f.close } }
      let(:input) { { path: temp_file.path } }

      after { temp_file.unlink }

      it 'returns success with file content' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include('test content')
      end
    end

    context 'with missing file' do
      let(:input) { { path: '/nonexistent/file/path.txt' } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include('No such file or directory')
      end
    end

    context 'without path parameter' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
      end
    end

    context 'with large file' do
      let(:temp_file) do
        Tempfile.new('large').tap { |f| f.write('x' * 60_000); f.close }
      end
      let(:input) { { path: temp_file.path } }

      after { temp_file.unlink }

      it 'truncates output to 50KB' do
        result = executor.call
        expect(result.data[:output].length).to be <= 50_000
      end
    end
  end
end
