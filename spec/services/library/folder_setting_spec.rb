# frozen_string_literal: true

require "rails_helper"

RSpec.describe Library::FolderSetting do
  let(:root) { Pathname.new(Dir.mktmpdir("library")) }

  after { FileUtils.remove_entry(root) }

  it "is on by default when the folder exists" do
    expect(described_class.enabled?(root: root)).to be(true)
  end

  it "is off by default when the folder is missing" do
    expect(described_class.enabled?(root: root.join("nope"))).to be(false)
  end

  it "can be switched off and on" do
    described_class.enabled = false
    expect(described_class.enabled?(root: root)).to be(false)

    described_class.enabled = true
    expect(described_class.enabled?(root: root)).to be(true)
  end

  it "names the host folder from the mounted path" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("HIVEMIND_LIBRARY_HOST_DIR", anything).and_return("/Users/ann/Hivemind Library")

    expect(described_class.folder_name).to eq("Hivemind Library")
  end
end
