# frozen_string_literal: true

require "rails_helper"

RSpec.describe Library::FolderScan do
  include ActiveJob::TestHelper

  let(:root) { Pathname.new(Dir.mktmpdir("library")) }
  let!(:agent) { create(:agent) }
  let(:embedding) { Array.new(768) { |i| (i % 10) * 0.1 } }

  before do
    allow(Memory::Embedding).to receive(:generate).and_return(embedding)
    ActiveJob::Base.queue_adapter = :test
  end

  after { FileUtils.remove_entry(root) if root.exist? }

  def put(name, body = "hello library world", age: 1.minute)
    path = root.join(name)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, body)
    File.utime(age.ago.to_time, age.ago.to_time, path)
    path
  end

  def scan
    result = described_class.new(root: root).call
    perform_enqueued_jobs
    result
  end

  def docs
    KnowledgeDocument.where.not(library_path: nil)
  end

  it "ingests a new file once with its relative path" do
    put("notes/handbook.txt")

    result = scan

    expect(result.added).to eq(1)
    doc = docs.sole
    expect(doc.library_path).to eq("notes/handbook.txt")
    expect(doc.title).to eq("handbook")
    expect(doc.agent).to eq(agent)
    expect(doc.status).to eq("ready")
    expect(doc.chunks.count).to eq(1)
  end

  it "ingests pdfs as pdf documents" do
    put("report.pdf", "%PDF-1.4")

    scan

    expect(docs.sole.source_type).to eq("pdf")
  end

  it "skips an unchanged file on rescan" do
    put("a.txt")
    scan

    result = nil
    expect { result = described_class.new(root: root).call }.not_to have_enqueued_job(KnowledgeIngestionJob)
    expect(result.added).to eq(0)
    expect(result.updated).to eq(0)
    expect(result.unchanged).to eq(1)
    expect(docs.count).to eq(1)
  end

  it "re-ingests a changed file and replaces its old chunks" do
    path = put("a.txt", "first version")
    scan
    old_ids = docs.sole.chunks.pluck(:id)

    File.write(path, "second version is longer")
    File.utime(30.seconds.ago.to_time, 30.seconds.ago.to_time, path)
    result = scan

    expect(result.updated).to eq(1)
    doc = docs.sole
    expect(doc.chunks.pluck(:content)).to eq([ "second version is longer" ])
    expect(doc.chunks.pluck(:id) & old_ids).to be_empty
    expect(doc.status).to eq("ready")
  end

  it "marks a deleted file removed and keeps its chunks" do
    path = put("a.txt")
    scan
    path.delete

    result = scan

    expect(result.removed).to eq(1)
    doc = docs.sole
    expect(doc.removed_at).to be_present
    expect(doc.chunks.count).to eq(1)
  end

  it "brings a removed file back when it reappears" do
    path = put("a.txt")
    scan
    path.delete
    scan
    put("a.txt")

    scan

    doc = docs.sole
    expect(doc.removed_at).to be_nil
    expect(doc.status).to eq("ready")
  end

  it "does not mark anything removed when the folder itself is missing" do
    put("a.txt")
    scan
    FileUtils.rm_rf(root)

    result = scan

    expect(result.removed).to eq(0)
    expect(docs.sole.removed_at).to be_nil
  end

  it "skips hidden, temp, partial and unsupported files" do
    put(".hidden.txt")
    put(".secret/inside.txt")
    put("~$draft.txt")
    put(".DS_Store")
    put("movie.crdownload")
    put("big.pdf.part")
    put("photo.png")
    put("good.md")

    scan

    expect(docs.pluck(:library_path)).to eq([ "good.md" ])
  end

  it "skips files still being written" do
    put("new.txt", age: 1.second)

    expect(scan.added).to eq(0)
  end

  it "skips files over the size cap" do
    stub_const("Library::FolderScan::MAX_BYTES", 5)
    put("huge.txt", "more than five bytes")

    expect(scan.added).to eq(0)
  end

  it "refuses symlinks pointing outside the library" do
    outside = Pathname.new(Dir.mktmpdir("outside"))
    File.write(outside.join("secret.txt"), "top secret")
    File.utime(1.minute.ago.to_time, 1.minute.ago.to_time, outside.join("secret.txt"))
    File.symlink(outside.join("secret.txt"), root.join("link.txt"))
    File.symlink(outside, root.join("linked_dir"))

    result = scan

    expect(result.added).to eq(0)
    expect(docs.count).to eq(0)
  ensure
    FileUtils.remove_entry(outside) if outside
  end

  it "records the scan on the folder settings" do
    put("a.txt")

    scan

    last = Library::FolderSetting.last_scan
    expect(last["added"]).to eq(1)
    expect(Time.zone.parse(last["at"])).to be_within(1.minute).of(Time.current)
  end

  it "does nothing with no agent to own the documents" do
    Agent.destroy_all
    put("a.txt")

    expect(scan.added).to eq(0)
  end
end
