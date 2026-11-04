# frozen_string_literal: true

require "rails_helper"

RSpec.describe "importmap" do
  it "pins marked to a vendored file instead of a CDN" do
    pin = File.readlines(Rails.root.join("config/importmap.rb")).grep(/pin "marked"/).first

    expect(pin).not_to include("http")
    expect(Rails.root.join("vendor/javascript/marked.js")).to exist
  end
end
