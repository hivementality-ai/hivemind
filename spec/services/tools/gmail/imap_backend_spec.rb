# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Gmail::ImapBackend, type: :service do
  addr = Struct.new(:name, :mailbox, :host)
  env = Struct.new(:from, :to, :subject, :date)
  msg = Struct.new(:attr)

  let(:imap) { instance_double(Net::IMAP, login: nil, logout: nil, disconnect: nil, select: nil) }
  let(:alice) { addr.new("Alice", "alice", "example.com") }
  let(:me) { addr.new("Me", "me", "gmail.com") }
  let(:envelope_class) { env }
  let(:msg_class) { msg }

  before do
    create(:vault_entry, namespace: "google", key: "gmail_address", value: "me@gmail.com")
    create(:vault_entry, namespace: "google", key: "gmail_app_password", value: "abcd efgh ijkl mnop")
    allow(Net::IMAP).to receive(:new).with("imap.gmail.com", port: 993, ssl: true).and_return(imap)
  end

  def run(input)
    described_class.new(input: input).call
  end

  def summary(uid, subject, flags: [ :Seen ])
    msg_class.new({ "UID" => uid, "FLAGS" => flags, "ENVELOPE" => envelope_class.new([ alice ], [ me ], subject, "Thu, 12 Mar 2026") })
  end

  def full_message(subject)
    msg_class.new({
      "ENVELOPE" => envelope_class.new([ alice ], [ me ], subject, "Thu, 12 Mar 2026"),
      "BODY[TEXT]" => "Hi there",
      "BODY[HEADER.FIELDS (MESSAGE-ID)]" => "Message-ID: <m1@example.com>\r\n"
    })
  end

  describe ".configured?" do
    it "is true with an address and app password" do
      expect(described_class.configured?).to be true
    end

    it "is false when the app password is missing" do
      VaultEntry.find_by!(namespace: "google", key: "gmail_app_password").destroy
      expect(described_class.configured?).to be false
    end
  end

  it "lists the inbox newest first for inbox, list and read" do
    allow(imap).to receive(:uid_search).with([ "ALL" ]).and_return([ 1, 2 ])
    allow(imap).to receive(:uid_fetch).with([ 1, 2 ], anything).and_return([ summary(1, "Old"), summary(2, "New", flags: []) ])

    %w[inbox list read].each do |action|
      response = run("action" => action)
      expect(response.success?).to be true
      expect(response.data[:output]).to include("[2] Alice <alice@example.com> — New")
      expect(response.data[:output].index("New")).to be < response.data[:output].index("Old")
    end
  end

  it "reads the folder it is given" do
    allow(imap).to receive(:uid_search).and_return([])

    run("action" => "inbox", "folder" => "[Gmail]/Sent Mail")

    expect(imap).to have_received(:select).with("[Gmail]/Sent Mail")
  end

  it "translates Gmail search operators for search" do
    allow(imap).to receive(:uid_search).and_return([ 5 ])
    allow(imap).to receive(:uid_fetch).and_return([ summary(5, "Invoice") ])

    response = run("action" => "search", "query" => "from:alice@example.com subject:invoice")

    expect(imap).to have_received(:uid_search).with(%w[FROM alice@example.com SUBJECT invoice])
    expect(response.data[:output]).to include("Invoice")
  end

  it "requires a query to search" do
    expect(run("action" => "search", "query" => "").error).to include("No query provided")
  end

  describe "get" do
    before { allow(imap).to receive(:uid_fetch).with(7, anything).and_return([ full_message("Hello") ]) }

    it "reads a message by uid" do
      response = run("action" => "get", "uid" => "7")
      expect(response.data[:output]).to include("From: Alice <alice@example.com>", "Subject: Hello", "Hi there")
    end

    it "accepts message_id in place of uid" do
      expect(run("action" => "get", "message_id" => "7").success?).to be true
    end

    it "requires an id" do
      expect(run("action" => "get").error).to include("No uid provided")
    end
  end

  describe "send and reply" do
    let(:smtp) { instance_double(Net::SMTP, enable_starttls: nil) }
    let(:server) { instance_double(Net::SMTP, send_message: nil) }

    before do
      allow(Net::SMTP).to receive(:new).with("smtp.gmail.com", 587).and_return(smtp)
      allow(smtp).to receive(:start).and_yield(server)
    end

    it "sends through Gmail SMTP with the app password" do
      response = run("action" => "send", "to" => "bob@example.com", "subject" => "Hi", "body" => "Hello")

      expect(response.data[:output]).to include("Email sent to bob@example.com")
      expect(smtp).to have_received(:start).with("gmail.com", "me@gmail.com", "abcd efgh ijkl mnop", :login)
      expect(server).to have_received(:send_message).with(include("Subject: Hi"), "me@gmail.com", "bob@example.com")
    end

    it "requires to, subject and body" do
      expect(run("action" => "send", "to" => "bob@example.com").error).to include("required")
    end

    it "replies to the original sender with Re: and In-Reply-To" do
      allow(imap).to receive(:uid_fetch).with(9, anything).and_return([ full_message("Plans") ])

      response = run("action" => "reply", "message_id" => "9", "body" => "Sounds good")

      expect(response.data[:output]).to include("Reply sent to Alice <alice@example.com>: Re: Plans")
      expect(server).to have_received(:send_message).with(include("In-Reply-To: <m1@example.com>"), "me@gmail.com", anything)
    end

    it "requires an id and body to reply" do
      expect(run("action" => "reply", "uid" => "9", "body" => "").error).to include("uid and body required")
    end
  end

  it "explains in plain words that drafts need the Google connection" do
    response = run("action" => "draft")

    expect(response.success?).to be false
    expect(response.error).to include("Connect Google at /integrations")
  end

  it "wraps connection errors" do
    allow(Net::IMAP).to receive(:new).and_raise(SocketError, "no route")

    response = run("action" => "inbox")

    expect(response.success?).to be false
    expect(response.error).to include("Gmail error: no route")
  end
end
