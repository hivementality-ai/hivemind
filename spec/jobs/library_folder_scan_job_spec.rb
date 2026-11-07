# frozen_string_literal: true

require "rails_helper"

RSpec.describe LibraryFolderScanJob, type: :job do
  let(:root) { Pathname.new(Dir.mktmpdir("library")) }

  before { allow(Library::FolderSetting).to receive(:root).and_return(root) }

  after { FileUtils.remove_entry(root) }

  it "scans the library folder when it is on" do
    scan = instance_double(Library::FolderScan, call: nil)
    allow(Library::FolderScan).to receive(:new).with(root: root).and_return(scan)

    described_class.perform_now

    expect(scan).to have_received(:call)
  end

  it "does not scan when the setting is off" do
    Library::FolderSetting.enabled = false
    allow(Library::FolderScan).to receive(:new)

    described_class.perform_now

    expect(Library::FolderScan).not_to have_received(:new)
  end

  it "is scheduled every few minutes" do
    schedule = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))

    entry = schedule.values.find { |job| job["class"] == "LibraryFolderScanJob" }
    expect(entry["cron"]).to eq("*/5 * * * *")
  end
end
