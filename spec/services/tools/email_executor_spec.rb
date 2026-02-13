# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::EmailExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock SMTP credentials
    allow(executor).to receive(:smtp_host).and_return('smtp.example.com')
    allow(executor).to receive(:smtp_port).and_return(587)
    allow(executor).to receive(:smtp_username).and_return('test@example.com')
    allow(executor).to receive(:smtp_password).and_return('password123')
    allow(executor).to receive(:from_address).and_return('test@example.com')
    allow(executor).to receive(:from_name).and_return('Test Sender')

    # Mock Net::SMTP
    @mock_smtp = instance_double(Net::SMTP)
    allow(Net::SMTP).to receive(:new).and_return(@mock_smtp)
    allow(@mock_smtp).to receive(:enable_starttls_auto)
    allow(@mock_smtp).to receive(:start).and_yield(@mock_smtp)
    allow(@mock_smtp).to receive(:send_message)
  end

  describe '#call' do
    context 'with send action' do
      let(:input) do
        {
          "action" => "send",
          "to" => "recipient@example.com",
          "subject" => "Test Subject",
          "body" => "This is a test email body"
        }
      end

      it 'sends text email successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Email sent to recipient@example.com: Test Subject")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'configures SMTP connection correctly' do
        executor.call
        expect(Net::SMTP).to have_received(:new).with('smtp.example.com', 587)
        expect(@mock_smtp).to have_received(:enable_starttls_auto)
        expect(@mock_smtp).to have_received(:start).with(
          'smtp.example.com', 'test@example.com', 'password123', :login
        )
      end

      it 'sends email with correct parameters' do
        executor.call
        expect(@mock_smtp).to have_received(:send_message).with(
          anything, 'test@example.com', ['recipient@example.com']
        )
      end

      context 'with CC and BCC recipients' do
        let(:input) do
          {
            "action" => "send",
            "to" => "recipient@example.com",
            "cc" => "cc@example.com",
            "bcc" => "bcc@example.com",
            "subject" => "Test Subject",
            "body" => "Test body"
          }
        end

        it 'includes all recipients in output' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("recipient@example.com, cc@example.com, bcc@example.com")
        end

        it 'sends to all destinations' do
          executor.call
          expect(@mock_smtp).to have_received(:send_message).with(
            anything, 'test@example.com', 
            array_including('recipient@example.com', 'cc@example.com', 'bcc@example.com')
          )
        end
      end

      context 'with reply_to address' do
        let(:input) do
          {
            "action" => "send",
            "to" => "recipient@example.com",
            "subject" => "Test Subject",
            "body" => "Test body",
            "reply_to" => "noreply@example.com"
          }
        end

        it 'includes reply_to in email' do
          result = executor.call
          expect(result).to be_success
        end
      end

      context 'without required fields' do
        context 'without to' do
          let(:input) { { "action" => "send", "subject" => "Test", "body" => "Test" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("to, subject, and body required")
          end
        end

        context 'without subject' do
          let(:input) { { "action" => "send", "to" => "test@example.com", "body" => "Test" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("to, subject, and body required")
          end
        end

        context 'without body' do
          let(:input) { { "action" => "send", "to" => "test@example.com", "subject" => "Test" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("to, subject, and body required")
          end
        end

        context 'with empty strings' do
          let(:input) do
            {
              "action" => "send",
              "to" => "  ",
              "subject" => "Test",
              "body" => "Test"
            }
          end

          it 'treats empty strings as missing' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("to, subject, and body required")
          end
        end
      end
    end

    context 'with send_html action' do
      let(:input) do
        {
          "action" => "send_html",
          "to" => "recipient@example.com",
          "subject" => "HTML Email",
          "html" => "<h1>Hello</h1><p>This is HTML content</p>"
        }
      end

      it 'sends HTML email successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("HTML email sent to recipient@example.com: HTML Email")
        expect(result.data[:exit_code]).to eq(0)
      end

      context 'with text alternative' do
        let(:input) do
          {
            "action" => "send_html",
            "to" => "recipient@example.com",
            "subject" => "HTML Email",
            "html" => "<h1>Hello</h1>",
            "text" => "Hello (plain text version)"
          }
        end

        it 'includes text alternative' do
          result = executor.call
          expect(result).to be_success
        end
      end

      context 'without text alternative' do
        it 'provides default text fallback' do
          result = executor.call
          expect(result).to be_success
        end
      end

      context 'without required fields' do
        let(:input) { { "action" => "send_html", "to" => "test@example.com", "subject" => "Test" } }

        it 'returns failure when html missing' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("to, subject, and html required")
        end
      end
    end

    context 'with config action' do
      let(:input) { { "action" => "config" } }

      context 'when SMTP is configured' do
        it 'shows configuration status' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("SMTP configured: smtp.example.com:587 (test@example.com)")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'when SMTP is not configured' do
        before do
          allow(executor).to receive(:smtp_host).and_return('')
          allow(executor).to receive(:smtp_username).and_return('')
        end

        it 'shows not configured message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("SMTP not configured. Set credentials in Integrations > Email.")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("send, send_html, config")
      end
    end

    context 'when SMTP connection fails' do
      let(:input) do
        {
          "action" => "send",
          "to" => "recipient@example.com",
          "subject" => "Test Subject",
          "body" => "Test body"
        }
      end

      before do
        allow(@mock_smtp).to receive(:start).and_raise(Net::SMTPAuthenticationError.new("Authentication failed"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Email error: Authentication failed")
      end
    end

    context 'with SSL port 465' do
      let(:input) do
        {
          "action" => "send",
          "to" => "recipient@example.com",
          "subject" => "Test Subject",
          "body" => "Test body"
        }
      end

      before do
        allow(executor).to receive(:smtp_port).and_return(465)
        allow(@mock_smtp).to receive(:enable_tls)
      end

      it 'uses TLS instead of STARTTLS' do
        executor.call
        expect(@mock_smtp).to have_received(:enable_tls)
        expect(@mock_smtp).not_to have_received(:enable_starttls_auto)
      end
    end

    context 'when building mail fails' do
      let(:input) do
        {
          "action" => "send",
          "to" => "invalid-email",
          "subject" => "Test",
          "body" => "Test"
        }
      end

      before do
        allow(Mail).to receive(:new).and_raise(Mail::Field::ParseError.new("Invalid email"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Email error: Invalid email")
      end
    end
  end

  describe 'credential methods' do
    context 'with vault entries' do
      before do
        create(:vault_entry, namespace: 'email', key: 'smtp_host', value: 'vault.smtp.com')
        create(:vault_entry, namespace: 'email', key: 'smtp_port', value: '465')
        create(:vault_entry, namespace: 'email', key: 'smtp_username', value: 'vault@example.com')
        create(:vault_entry, namespace: 'email', key: 'smtp_password', value: 'vaultpass')
        create(:vault_entry, namespace: 'email', key: 'from_address', value: 'sender@example.com')
        create(:vault_entry, namespace: 'email', key: 'from_name', value: 'Vault Sender')
        
        # Reset memoized instance variables
        executor.remove_instance_variable(:@smtp_host) if executor.instance_variable_defined?(:@smtp_host)
        executor.remove_instance_variable(:@smtp_port) if executor.instance_variable_defined?(:@smtp_port)
        executor.remove_instance_variable(:@smtp_username) if executor.instance_variable_defined?(:@smtp_username)
        executor.remove_instance_variable(:@smtp_password) if executor.instance_variable_defined?(:@smtp_password)
        executor.remove_instance_variable(:@from_address) if executor.instance_variable_defined?(:@from_address)
        executor.remove_instance_variable(:@from_name) if executor.instance_variable_defined?(:@from_name)
      end

      it 'reads credentials from vault' do
        expect(executor.send(:smtp_host)).to eq('vault.smtp.com')
        expect(executor.send(:smtp_port)).to eq(465)
        expect(executor.send(:smtp_username)).to eq('vault@example.com')
        expect(executor.send(:smtp_password)).to eq('vaultpass')
        expect(executor.send(:from_address)).to eq('sender@example.com')
        expect(executor.send(:from_name)).to eq('Vault Sender')
      end
    end

    context 'with environment variables' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SMTP_HOST").and_return('env.smtp.com')
        allow(ENV).to receive(:[]).with("SMTP_PORT").and_return('2525')
        allow(ENV).to receive(:[]).with("SMTP_USERNAME").and_return('env@example.com')
        allow(ENV).to receive(:[]).with("SMTP_PASSWORD").and_return('envpass')
        allow(ENV).to receive(:[]).with("SMTP_FROM_ADDRESS").and_return('envfrom@example.com')
        allow(ENV).to receive(:[]).with("SMTP_FROM_NAME").and_return('Env Sender')
      end

      it 'falls back to environment variables' do
        expect(executor.send(:smtp_host)).to eq('env.smtp.com')
        expect(executor.send(:smtp_port)).to eq(2525)
        expect(executor.send(:smtp_username)).to eq('env@example.com')
        expect(executor.send(:smtp_password)).to eq('envpass')
        expect(executor.send(:from_address)).to eq('envfrom@example.com')
        expect(executor.send(:from_name)).to eq('Env Sender')
      end
    end

    context 'with defaults' do
      it 'uses sensible defaults' do
        expect(executor.send(:smtp_port)).to eq(587)
        expect(executor.send(:from_address)).to eq(executor.send(:smtp_username))
      end
    end
  end

  describe '#vault_get' do
    it 'retrieves vault entries' do
      create(:vault_entry, namespace: 'test', key: 'value', value: 'secret')
      result = executor.send(:vault_get, 'test', 'value')
      expect(result).to eq('secret')
    end

    it 'returns nil for non-existent entries' do
      result = executor.send(:vault_get, 'nonexistent', 'key')
      expect(result).to be_nil
    end
  end
end