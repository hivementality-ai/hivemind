# frozen_string_literal: true

module Hivemind
  # CalVer: YYYY.MM.PATCH
  # Source of truth: .hivemind_version file baked into the image at Docker build
  # time from the git tag. The HIVEMIND_VERSION env var is only a fallback: the
  # deploy compose file passes the operator's .env into the container, so a
  # stale pin there would misreport what's actually running.
  # Then: git describe --tags (local development). Last resort: "dev".

  BAKED_VERSION = begin
    path = Rails.root.join(".hivemind_version")
    path.exist? ? path.read.strip.presence : nil
  rescue StandardError
    nil
  end
  private_constant :BAKED_VERSION

  VERSION = (
    BAKED_VERSION ||
    ENV["HIVEMIND_VERSION"].presence ||
    `git describe --tags --abbrev=0 2>/dev/null`.strip.delete_prefix("v").presence ||
    "dev"
  ).freeze

  VERSION_FULL = (
    BAKED_VERSION ||
    ENV["HIVEMIND_VERSION"].presence ||
    `git describe --tags 2>/dev/null`.strip.delete_prefix("v").presence ||
    "dev"
  ).freeze

  def self.version
    VERSION
  end

  def self.version_full
    VERSION_FULL
  end
end
