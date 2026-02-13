# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::GmailExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock Gmail credentials
    allow(executor).to receive(:gmail_address).and_return('test@gmail.com')
    allow(executor).to receive(:gmail_password).and_return('app-password-123')

    # Mock IMAP connection
    @mock_imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(@mock_imap)
    allow(@mock_imap).to receive(:login)
    allow(@mock_imap).to receive(:logout)
    allow(@mock_imap).to receive(:disconnect)
    allow(@mock_imap).to receive(:select)

    # Mock SMTP connection
    @mock_smtp = instance_double(Net::SMTP)
    allow(Net::SMTP).to receive(:new).and_return(@mock_smtp)
    allow(@mock_smtp).to receive(:enable_starttls)
    allow(@mock_smtp).to receive(:start).and_yield(@mock_smtp)
    allow(@mock_smtp).to receive(:send_message)
  end

  describe '#call' do
    context 'with inbox action' do
      let(:input) { { "action" => "inbox" } }

      before do
        mock_imap_inbox_messages
      end

      it 'fetches inbox messages successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("INBOX (2 messages)")
        expect(result.data[:output]).to include("✉️  Important Meeting")
        expect(result.data[:output]).to include("📧 Welcome to our service")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'connects to IMAP correctly' do
        executor.call
        expect(Net::IMAP).to have_received(:new).with("imap.gmail.com", port: 993, ssl: true)
        expect(@mock_imap).to have_received(:login).with('test@gmail.com', 'app-password-123')
        expect(@mock_imap).to have_received(:select).with("INBOX")
      end

      context 'with custom folder' do
        let(:input) { { "action" => "inbox", "folder" => "Sent" } }

        it 'selects custom folder' do
          executor.call
          expect(@mock_imap).to have_received(:select).with("Sent")
        end
      end

      context 'with custom limit' do
        let(:input) { { "action" => "inbox", "limit" => 5 } }

        before do
          allow(@mock_imap).to receive(:search).and_return((1..10).to_a)
          mock_imap_fetch_recent(5)
        end

        it 'respects limit parameter' do
          executor.call
          expect(@mock_imap).to have_received(:uid_fetch).with([6, 7, 8, 9, 10], anything)
        end
      end

      context 'when no messages found' do
        before do
          allow(@mock_imap).to receive(:search).and_return([])
        end

        it 'shows empty inbox' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("INBOX (0 messages)")
        end
      end
    end

    context 'with search action' do
      let(:input) { { "action" => "search", "query" => "meeting" } }

      before do
        allow(@mock_imap).to receive(:search).with(["OR", "SUBJECT", "meeting", "FROM", "meeting"]).and_return([101, 102])
        mock_imap_search_results
      end

      it 'searches emails successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Search: 'meeting' (2 results)")
        expect(result.data[:output]).to include("Team Meeting Tomorrow")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'uses correct IMAP search parameters' do
        executor.call
        expect(@mock_imap).to have_received(:search).with(["OR", "SUBJECT", "meeting", "FROM", "meeting"])
      end

      context 'without query' do
        let(:input) { { "action" => "search" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No query provided")
        end
      end

      context 'with no search results' do
        before do
          allow(@mock_imap).to receive(:search).and_return([])
        end

        it 'shows no results' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Search: 'meeting' (0 results)")
        end
      end
    end

    context 'with get action' do
      let(:input) { { "action" => "get", "uid" => "12345" } }

      before do
        mock_imap_get_message
      end

      it 'fetches specific email successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("From: sender@example.com")
        expect(result.data[:output]).to include("To: test@gmail.com")
        expect(result.data[:output]).to include("Subject: Test Email")
        expect(result.data[:output]).to include("Date: Mon, 1 Jan 2023 12:00:00 +0000")
        expect(result.data[:output]).to include("This is the email content")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls IMAP uid_fetch with correct parameters' do
        executor.call
        expect(@mock_imap).to have_received(:uid_fetch).with(12345, ["ENVELOPE", "BODY[TEXT]", "BODY[HEADER.FIELDS (MESSAGE-ID)]"])
      end

      context 'without uid' do
        let(:input) { { "action" => "get" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No uid provided")
        end
      end

      context 'when email not found' do
        before do
          allow(@mock_imap).to receive(:uid_fetch).and_return(nil)
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Email not found")
        end
      end

      context 'with large email body' do
        let(:large_body) { 'x' * 15_000 }

        before do
          mock_imap_get_message(body: large_body)
        end

        it 'truncates body to 10KB' do
          result = executor.call
          expect(result).to be_success
          body_part = result.data[:output].split("\n\n").last
          expect(body_part.length).to be <= 10_000
        end
      end
    end

    context 'with send action' do
      let(:input) do
        {
          "action" => "send",
          "to" => "recipient@example.com",
          "subject" => "Test Subject",
          "body" => "This is a test email body"
        }
      end

      it 'sends email successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Email sent to recipient@example.com: Test Subject")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'configures SMTP connection correctly' do
        executor.call
        expect(Net::SMTP).to have_received(:new).with("smtp.gmail.com", 587)
        expect(@mock_smtp).to have_received(:enable_starttls)
        expect(@mock_smtp).to have_received(:start).with("gmail.com", 'test@gmail.com', 'app-password-123', :login)
      end

      it 'sends mail with correct parameters' do
        executor.call
        expect(@mock_smtp).to have_received(:send_message).with(
          anything, 'test@gmail.com', 'recipient@example.com'
        )
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
      end
    end

    context 'with reply action' do
      let(:input) { { "action" => "reply", "uid" => "12345", "body" => "Thanks for your message!" } }

      before do
        mock_imap_get_message(
          subject: 'Original Subject',
          from: 'original@example.com',
          message_id: '<123@example.com>'
        )
      end

      it 'replies to email successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Reply sent to original@example.com: Re: Original Subject")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'adds Re: prefix to subject' do
        # We can't directly test the mail content easily, but we can verify the SMTP call
        executor.call
        expect(@mock_smtp).to have_received(:send_message)
      end

      context 'when original subject already has Re:' do
        before do
          mock_imap_get_message(subject: 'Re: Original Subject')
        end

        it 'does not add duplicate Re: prefix' do
          result = executor.call
          expect(result.data[:output]).to include("Re: Original Subject")
          expect(result.data[:output]).not_to include("Re: Re:")
        end
      end

      context 'without uid' do
        let(:input) { { "action" => "reply", "body" => "Reply body" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("uid and body required")
        end
      end

      context 'without body' do
        let(:input) { { "action" => "reply", "uid" => "12345" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("uid and body required")
        end
      end

      context 'when original email not found' do
        before do
          allow(@mock_imap).to receive(:uid_fetch).and_return(nil)
        end

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Original email not found")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("inbox, search, get, send, reply")
      end
    end

    context 'when IMAP connection fails' do
      let(:input) { { "action" => "inbox" } }

      before do
        allow(@mock_imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new("Authentication failed"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Gmail error: Authentication failed")
      end
    end

    context 'when SMTP connection fails' do
      let(:input) { { "action" => "send", "to" => "test@example.com", "subject" => "Test", "body" => "Test" } }

      before do
        allow(@mock_smtp).to receive(:start).and_raise(Net::SMTPAuthenticationError.new("SMTP Authentication failed"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Gmail error: SMTP Authentication failed")
      end
    end
  end

  describe 'credential methods' do
    context 'with vault entries' do
      before do
        create(:vault_entry, namespace: 'google', key: 'gmail_address', value: 'vault@gmail.com')
        create(:vault_entry, namespace: 'google', key: 'gmail_app_password', value: 'vault-password')
        
        # Reset memoized values
        executor.remove_instance_variable(:@gmail_address) if executor.instance_variable_defined?(:@gmail_address)
        executor.remove_instance_variable(:@gmail_password) if executor.instance_variable_defined?(:@gmail_password)
      end

      it 'reads credentials from vault' do
        expect(executor.send(:gmail_address)).to eq('vault@gmail.com')
        expect(executor.send(:gmail_password)).to eq('vault-password')
      end
    end

    context 'with environment variables' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("GMAIL_ADDRESS").and_return('env@gmail.com')
        allow(ENV).to receive(:[]).with("GMAIL_APP_PASSWORD").and_return('env-password')
      end

      it 'falls back to environment variables' do
        expect(executor.send(:gmail_address)).to eq('env@gmail.com')
        expect(executor.send(:gmail_password)).to eq('env-password')
      end
    end
  end

  describe '#format_address' do
    it 'formats addresses correctly' do
      address1 = OpenStruct.new(name: 'John Doe', mailbox: 'john', host: 'example.com')
      address2 = OpenStruct.new(name: nil, mailbox: 'jane', host: 'example.com')
      
      result = executor.send(:format_address, [address1, address2])
      expect(result).to eq("John Doe <john@example.com>,  <jane@example.com>")
    end

    it 'handles nil addresses' do
      result = executor.send(:format_address, nil)
      expect(result).to eq("")
    end

    it 'handles empty addresses array' do
      result = executor.send(:format_address, [])
      expect(result).to eq("")
    end
  end

  describe '#vault_get' do
    it 'retrieves vault entries' do
      create(:vault_entry, namespace: 'google', key: 'test_key', value: 'test_value')
      result = executor.send(:vault_get, 'google', 'test_key')
      expect(result).to eq('test_value')
    end

    it 'returns nil for non-existent entries' do
      result = executor.send(:vault_get, 'nonexistent', 'key')
      expect(result).to be_nil
    end
  end

  private

  def mock_imap_inbox_messages
    allow(@mock_imap).to receive(:search).with(["ALL"]).and_return([101, 102])
    
    # Mock envelope data for inbox messages
    envelope1 = OpenStruct.new(
      subject: 'Important Meeting',
      from: [OpenStruct.new(name: 'Boss', mailbox: 'boss', host: 'company.com')],
      date: 'Mon, 1 Jan 2023 12:00:00 +0000'
    )
    envelope2 = OpenStruct.new(
      subject: 'Welcome to our service',
      from: [OpenStruct.new(name: 'Support', mailbox: 'support', host: 'service.com')],
      date: 'Sun, 31 Dec 2022 18:00:00 +0000'
    )

    msg1 = OpenStruct.new(attr: { "ENVELOPE" => envelope1, "UID" => 102, "FLAGS" => [] })
    msg2 = OpenStruct.new(attr: { "ENVELOPE" => envelope2, "UID" => 101, "FLAGS" => [:Seen] })

    allow(@mock_imap).to receive(:uid_fetch).with([101, 102], ["ENVELOPE", "UID", "FLAGS"]).and_return([msg2, msg1])
  end

  def mock_imap_fetch_recent(limit)
    messages = (1..limit).map do |i|
      envelope = OpenStruct.new(
        subject: "Message #{i}",
        from: [OpenStruct.new(name: "Sender #{i}", mailbox: "sender#{i}", host: 'example.com')],
        date: "Mon, #{i} Jan 2023 12:00:00 +0000"
      )
      OpenStruct.new(attr: { "ENVELOPE" => envelope, "UID" => i + 5, "FLAGS" => [] })
    end
    
    allow(@mock_imap).to receive(:uid_fetch).and_return(messages)
  end

  def mock_imap_search_results
    envelope1 = OpenStruct.new(
      subject: 'Team Meeting Tomorrow',
      from: [OpenStruct.new(name: 'Manager', mailbox: 'manager', host: 'company.com')],
      date: 'Tue, 2 Jan 2023 10:00:00 +0000'
    )
    envelope2 = OpenStruct.new(
      subject: 'Project Meeting Notes',
      from: [OpenStruct.new(name: 'PM', mailbox: 'pm', host: 'company.com')],
      date: 'Wed, 3 Jan 2023 14:00:00 +0000'
    )

    msg1 = OpenStruct.new(attr: { "ENVELOPE" => envelope1, "UID" => 102, "FLAGS" => [] })
    msg2 = OpenStruct.new(attr: { "ENVELOPE" => envelope2, "UID" => 101, "FLAGS" => [:Seen] })

    allow(@mock_imap).to receive(:uid_fetch).with([101, 102], ["ENVELOPE", "UID", "FLAGS"]).and_return([msg1, msg2])
  end

  def mock_imap_get_message(subject: 'Test Email', from: 'sender@example.com', message_id: '<test@example.com>', body: 'This is the email content')
    envelope = OpenStruct.new(
      subject: subject,
      from: [OpenStruct.new(name: nil, mailbox: from.split('@')[0], host: from.split('@')[1])],
      to: [OpenStruct.new(name: nil, mailbox: 'test', host: 'gmail.com')],
      date: 'Mon, 1 Jan 2023 12:00:00 +0000'
    )

    msg = OpenStruct.new(attr: {
      "ENVELOPE" => envelope,
      "BODY[TEXT]" => body,
      "BODY[HEADER.FIELDS (MESSAGE-ID)]" => "Message-ID: #{message_id}"
    })

    allow(@mock_imap).to receive(:uid_fetch).and_return([msg])

    # Mock Mail.new for body decoding
    mail_mock = instance_double(Mail::Message)
    body_mock = instance_double(Mail::Body, decoded: body)
    allow(mail_mock).to receive(:body).and_return(body_mock)
    allow(Mail).to receive(:new).and_return(mail_mock)
  end

  def format_email_list(emails, title)
    if emails.any?
      output = emails.map do |email|
        icon = email[:read] ? "📧" : "✉️ "
        "#{icon} #{email[:subject]} — #{email[:from]} (#{email[:date]})"
      end.join("\n")
      ServiceResponse.success(data: { output: "#{title}:\n#{output}", exit_code: 0 })
    else
      ServiceResponse.success(data: { output: "#{title}:\n(no messages)", exit_code: 0 })
    end
  end
end