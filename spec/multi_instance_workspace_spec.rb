# frozen_string_literal: true

require "rails_helper"

# Regression guard for multi-instance isolation (`hivemind new`).
#
# Every place that `docker exec`s into the workspace sandbox must address it by
# this instance's Compose-derived container name, NOT a hardcoded
# "hivemind-workspace-1". Hardcoding it makes a second instance exec into the
# primary's workspace on the shared host Docker daemon — so one instance's agent
# work runs in another's sandbox and breaks when that container restarts.
RSpec.describe "multi-instance workspace container isolation" do
  # Only files that *define* the constant — files that merely reference
  # WorkspaceIo::WORKSPACE_CONTAINER reuse the derived value and are fine.
  files = Dir[Rails.root.join("app/**/*.rb")].select { |f| File.read(f).match?(/WORKSPACE_CONTAINER\s*=/) }

  it "covers every file that defines WORKSPACE_CONTAINER" do
    expect(files).not_to be_empty
  end

  files.each do |file|
    rel = Pathname.new(file).relative_path_from(Rails.root).to_s

    it "#{rel} does not hardcode the container name" do
      src = File.read(file)
      offending = src.lines.grep(/WORKSPACE_CONTAINER\s*=/).grep(/"hivemind-workspace-1"/)
      expect(offending).to be_empty,
        "#{rel} hardcodes \"hivemind-workspace-1\" — derive it from COMPOSE_PROJECT_NAME instead"
    end

    it "#{rel} derives the container name from COMPOSE_PROJECT_NAME" do
      assignment = File.read(file).lines.grep(/WORKSPACE_CONTAINER\s*=/).first
      expect(assignment).to match(/COMPOSE_PROJECT_NAME/),
        "#{rel} should set WORKSPACE_CONTAINER from ENV['COMPOSE_PROJECT_NAME']"
    end
  end
end
