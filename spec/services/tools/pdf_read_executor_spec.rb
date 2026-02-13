# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::PdfReadExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(Rails).to receive(:root).and_return(Pathname.new('/app'))
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:join).and_call_original
  end

  describe '#call' do
    context 'with read action' do
      let(:input) { { "action" => "read", "path" => "documents/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("This is the extracted text from the PDF document.\nSecond paragraph of content.")
      end

      it 'extracts PDF text successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("This is the extracted text from the PDF document")
        expect(result.data[:output]).to include("Second paragraph of content")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls Python script with correct parameters' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf"
        )
      end

      context 'with specific pages' do
        let(:input) { { "action" => "read", "path" => "documents/sample.pdf", "pages" => "1-3" } }

        it 'passes pages parameter to script' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--pages", "1-3"
          )
        end
      end

      context 'with markdown format' do
        let(:input) { { "action" => "read", "path" => "documents/sample.pdf", "format" => "markdown" } }

        it 'passes format parameter to script' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--format", "markdown"
          )
        end
      end

      context 'with both pages and markdown format' do
        let(:input) { { "action" => "read", "path" => "documents/sample.pdf", "pages" => "2", "format" => "markdown" } }

        it 'passes both parameters to script' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--pages", "2", "--format", "markdown"
          )
        end
      end

      context 'with default text format' do
        let(:input) { { "action" => "read", "path" => "documents/sample.pdf", "format" => "text" } }

        it 'does not pass format parameter for default text format' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf"
          )
        end
      end
    end

    context 'with default read action' do
      let(:input) { { "path" => "documents/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Default read action content")
      end

      it 'defaults to read when no action specified' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Default read action content")
      end
    end

    context 'with metadata action' do
      let(:input) { { "action" => "metadata", "path" => "documents/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Title: Sample Document\nAuthor: John Doe\nCreated: 2023-01-15\nPages: 5")
      end

      it 'extracts PDF metadata successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Title: Sample Document")
        expect(result.data[:output]).to include("Author: John Doe")
        expect(result.data[:output]).to include("Pages: 5")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls script with metadata flag' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--metadata"
        )
      end
    end

    context 'with tables action' do
      let(:input) { { "action" => "tables", "path" => "documents/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Table 1: Revenue Data\nQ1: $100k\nQ2: $150k\nQ3: $200k")
      end

      it 'extracts PDF tables successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Table 1: Revenue Data")
        expect(result.data[:output]).to include("Q1: $100k")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls script with tables flag' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--tables"
        )
      end

      context 'with specific page' do
        let(:input) { { "action" => "tables", "path" => "documents/sample.pdf", "page" => "3" } }

        it 'passes table page parameter' do
          executor.call
          expect(Open3).to have_received(:capture3).with(
            "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--tables", "--table-page", "3"
          )
        end
      end
    end

    context 'with absolute path within workspace' do
      let(:input) { { "action" => "read", "path" => "/workspace/pdfs/document.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/pdfs/document.pdf').and_return(true)
        mock_successful_pdf_extraction("Absolute path content")
      end

      it 'accepts absolute paths within workspace' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Absolute path content")
      end
    end

    context 'with path within Rails root' do
      let(:input) { { "action" => "read", "path" => "/app/test/fixtures/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/app/test/fixtures/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Rails root content")
      end

      it 'accepts paths within Rails root' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Rails root content")
      end
    end

    context 'without path parameter' do
      let(:input) { { "action" => "read" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'with empty path' do
      let(:input) { { "action" => "read", "path" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No path provided")
      end
    end

    context 'with path outside workspace' do
      let(:input) { { "action" => "read", "path" => "/etc/passwd" } }

      it 'returns access denied error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Access denied: path must be within /workspace")
      end
    end

    context 'with path traversal attempt' do
      let(:input) { { "action" => "read", "path" => "../../../etc/passwd" } }

      before do
        allow(File).to receive(:join).with('/workspace', '../../../etc/passwd').and_return('/etc/passwd')
      end

      it 'blocks path traversal' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Access denied: path must be within /workspace")
      end
    end

    context 'when file does not exist' do
      let(:input) { { "action" => "read", "path" => "documents/missing.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/missing.pdf').and_return(false)
      end

      it 'returns file not found error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("File not found: documents/missing.pdf")
      end
    end

    context 'when Python script fails' do
      let(:input) { { "action" => "read", "path" => "documents/corrupted.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/corrupted.pdf').and_return(true)
        allow(Open3).to receive(:capture3).and_return(['', 'Error: Invalid PDF format', double(success?: false)])
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Error: Invalid PDF format")
      end
    end

    context 'when Python script fails without stderr' do
      let(:input) { { "action" => "read", "path" => "documents/empty.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/empty.pdf').and_return(true)
        allow(Open3).to receive(:capture3).and_return(['', '', double(success?: false)])
      end

      it 'returns generic failure message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("PDF extraction failed")
      end
    end

    context 'with very large output' do
      let(:input) { { "action" => "read", "path" => "documents/large.pdf" } }
      let(:large_output) { 'x' * 150_000 }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/large.pdf').and_return(true)
        mock_successful_pdf_extraction(large_output)
      end

      it 'truncates output to 100KB' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output].length).to be <= Tools::PdfReadExecutor::MAX_OUTPUT
      end
    end

    context 'with very long error message' do
      let(:input) { { "action" => "read", "path" => "documents/error.pdf" } }
      let(:long_error) { 'Error: ' + ('x' * 600) }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/error.pdf').and_return(true)
        allow(Open3).to receive(:capture3).and_return(['', long_error, double(success?: false)])
      end

      it 'truncates error message to 500 chars' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error.length).to be <= 500
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid", "path" => "documents/sample.pdf" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("read, metadata, tables")
      end
    end

    context 'when Open3 raises exception' do
      let(:input) { { "action" => "read", "path" => "documents/sample.pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new("Python not found"))
      end

      it 'propagates the exception' do
        expect { executor.call }.to raise_error(Errno::ENOENT, "Python not found")
      end
    end

    context 'with complex file paths' do
      let(:input) { { "action" => "read", "path" => "client files/report (final).pdf" } }

      before do
        allow(File).to receive(:exist?).with('/workspace/client files/report (final).pdf').and_return(true)
        mock_successful_pdf_extraction("Complex filename content")
      end

      it 'handles files with spaces and special characters' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Complex filename content")
      end

      it 'passes correct path to Python script' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/client files/report (final).pdf"
        )
      end
    end

    context 'with numeric page parameter' do
      let(:input) { { "action" => "tables", "path" => "documents/sample.pdf", "page" => 5 } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Table from page 5")
      end

      it 'converts numeric page to string' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--tables", "--table-page", "5"
        )
      end
    end

    context 'with numeric pages parameter' do
      let(:input) { { "action" => "read", "path" => "documents/sample.pdf", "pages" => 3 } }

      before do
        allow(File).to receive(:exist?).with('/workspace/documents/sample.pdf').and_return(true)
        mock_successful_pdf_extraction("Content from page 3")
      end

      it 'converts numeric pages to string' do
        executor.call
        expect(Open3).to have_received(:capture3).with(
          "python3", "/app/lib/scripts/pdf_extract.py", "/workspace/documents/sample.pdf", "--pages", "3"
        )
      end
    end
  end

  describe 'private methods' do
    describe '#resolve_path' do
      before do
        allow(File).to receive(:exist?).and_return(true)
      end

      it 'resolves relative paths' do
        executor.instance_variable_set(:@input, { "path" => "test.pdf" })
        path = executor.send(:resolve_path)
        expect(path).to eq("/workspace/test.pdf")
      end

      it 'accepts absolute paths within workspace' do
        executor.instance_variable_set(:@input, { "path" => "/workspace/test.pdf" })
        path = executor.send(:resolve_path)
        expect(path).to eq("/workspace/test.pdf")
      end

      it 'accepts paths within Rails root' do
        executor.instance_variable_set(:@input, { "path" => "/app/test.pdf" })
        path = executor.send(:resolve_path)
        expect(path).to eq("/app/test.pdf")
      end

      it 'blocks external paths' do
        executor.instance_variable_set(:@input, { "path" => "/etc/passwd" })
        result = executor.send(:resolve_path)
        expect(result).to be_a(ServiceResponse)
        expect(result.error).to include("Access denied")
      end
    end

    describe '#execute_command' do
      it 'returns success response for successful command' do
        allow(Open3).to receive(:capture3).and_return(['output', '', double(success?: true)])
        result = executor.send(:execute_command, ['echo', 'test'])
        expect(result).to be_success
        expect(result.data[:output]).to eq('output')
      end

      it 'returns failure response for failed command' do
        allow(Open3).to receive(:capture3).and_return(['', 'error message', double(success?: false)])
        result = executor.send(:execute_command, ['false'])
        expect(result).to be_failure
        expect(result.error).to eq('error message')
      end
    end
  end

  private

  def mock_successful_pdf_extraction(output)
    allow(Open3).to receive(:capture3).and_return([output, '', double(success?: true)])
  end
end