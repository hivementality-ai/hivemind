# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "docker-compose.yml library mount" do
  let(:services) { YAML.load_file(File.expand_path("../../docker-compose.yml", __dir__)).fetch("services") }

  def library_mounts(name)
    services.fetch(name).fetch("volumes", []).select { |v| v.include?(":/library") }
  end

  it "mounts one host folder read-only into the web and system worker" do
    %w[app worker-system].each do |name|
      expect(library_mounts(name)).to eq([ "${HIVEMIND_LIBRARY_DIR:-/hivemind-library-unset}:/library:ro" ])
    end
  end

  it "mounts it nowhere else" do
    others = services.keys - %w[app worker-system]

    expect(others.flat_map { |name| library_mounts(name) }).to be_empty
  end
end
