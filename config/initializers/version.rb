# frozen_string_literal: true

module Hivemind
  # CalVer: YYYY.MM.PATCH
  # Source of truth: HIVEMIND_VERSION env var (set at Docker build time from git tag)
  # Fallback: git describe --tags (for local development)
  # Last resort: "dev"

  VERSION = (
    ENV["HIVEMIND_VERSION"].presence ||
    `git describe --tags --abbrev=0 2>/dev/null`.strip.delete_prefix("v").presence ||
    "dev"
  ).freeze

  VERSION_FULL = (
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
