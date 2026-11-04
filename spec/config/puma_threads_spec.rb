# frozen_string_literal: true

require "rails_helper"
require "puma/configuration"

RSpec.describe "Puma thread configuration" do
  around do |example|
    saved = ENV.delete("RAILS_MAX_THREADS")
    example.run
  ensure
    ENV["RAILS_MAX_THREADS"] = saved if saved
  end

  def puma_max_threads
    config = Puma::Configuration.new({}, {}) { |user_config| user_config.instance_eval(File.read(Rails.root.join("config/puma.rb"))) }
    config.clamp
    config.options[:max_threads]
  end

  def database_pool_size
    YAML.safe_load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true).dig("default", "max_connections").to_i
  end

  it "runs enough threads that sdk-proxy tool callbacks do not starve the UI" do
    expect(puma_max_threads).to be >= 10
  end

  it "keeps the database pool at least as large as the thread count" do
    expect(database_pool_size).to be >= puma_max_threads
  end

  it "follows RAILS_MAX_THREADS in both places" do
    ENV["RAILS_MAX_THREADS"] = "16"

    expect(puma_max_threads).to eq(16)
    expect(database_pool_size).to eq(16)
  end
end
