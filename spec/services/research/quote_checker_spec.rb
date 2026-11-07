# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::QuoteChecker do
  let(:source_text) do
    "Researchers found that the new error correction scheme reduces logical error rates by a factor of ten " \
      "across every tested configuration, which is a significant result."
  end
  let(:sources) { [ { url: "https://example.com/a", text: source_text } ] }
  let(:quote) { "the new error correction scheme reduces logical error rates by a factor of ten" }

  def check(report, srcs = sources)
    described_class.call(report: report, sources: srcs)
  end

  def statuses(result)
    result["results"].map { |r| r["status"] }
  end

  it "verifies a quote that appears in the source" do
    result = check(%(They said "#{quote}" in the paper. [A](https://example.com/a)))

    expect(statuses(result)).to eq([ "verified" ])
    expect(result["results"].first).to include("passage" => quote, "source_url" => "https://example.com/a")
    expect(result["summary"]).to eq("total" => 1, "verified" => 1, "unverified" => 0)
  end

  it "marks a long quote with a single changed word as unverified" do
    changed = quote.sub("ten", "nine")
    result = check(%(They said "#{changed}" in the paper.))

    expect(statuses(result)).to eq([ "unverified" ])
    expect(result["summary"]).to eq("total" => 1, "verified" => 0, "unverified" => 1)
  end

  it "ignores case and whitespace differences" do
    messy = quote.upcase.gsub(" ", "  \n ")

    expect(statuses(check(%("#{messy}")))).to eq([ "verified" ])
  end

  it "treats curly and straight quotes as equal in the report and the source" do
    srcs = [ { url: "u", text: "The team’s own words were “it isn’t clear that this scales to larger devices yet” today." } ]
    report = %(Per the team: “it isn't clear that this scales to larger devices yet”)

    expect(statuses(check(report, srcs))).to eq([ "verified" ])
  end

  it "treats en dashes, em dashes and hyphens as equal" do
    srcs = [ { url: "u", text: "A well-known result — the so-called threshold theorem – holds for noisy hardware at scale." } ]
    report = %("a well-known result - the so-called threshold theorem - holds for noisy hardware at scale")

    expect(statuses(check(report, srcs))).to eq([ "verified" ])
  end

  it "ignores punctuation at the edges of the quote" do
    expect(statuses(check(%("#{quote}," they wrote.")))).to eq([ "verified" ])
  end

  it "skips quotes shorter than eight words" do
    result = check(%(He called it "a significant result" in the paper and "the new error correction scheme".))

    expect(result["results"]).to eq([])
    expect(result["summary"]).to eq("total" => 0, "verified" => 0, "unverified" => 0)
  end

  it "counts a quote of exactly eight words" do
    srcs = [ { url: "u", text: "one two three four five six seven eight nine" } ]

    expect(statuses(check(%("one two three four five six seven eight"), srcs))).to eq([ "verified" ])
  end

  it "verifies against any source when the cited one lacks the passage" do
    srcs = [ { url: "https://example.com/b", text: "unrelated" }, sources.first ]
    result = check(%("#{quote}" [B](https://example.com/b)), srcs)

    expect(result["results"].first).to include("status" => "verified", "source_url" => "https://example.com/a")
  end

  it "keeps the cited url on an unverified quote" do
    result = check(%("#{quote.sub('ten', 'nine')}" [A](https://example.com/a)))

    expect(result["results"].first).to include("status" => "unverified", "source_url" => "https://example.com/a")
  end

  it "marks everything unverified when there are no sources" do
    expect(statuses(check(%("#{quote}"), []))).to eq([ "unverified" ])
  end

  it "only checks against the first 200 KB of a source" do
    padded = ("filler " * 40_000) + quote

    expect(statuses(check(%("#{quote}"), [ { url: "u", text: padded } ]))).to eq([ "unverified" ])
  end

  it "returns an empty result for a report without quotes" do
    expect(check("No quotes here.")).to eq("results" => [], "summary" => { "total" => 0, "verified" => 0, "unverified" => 0 })
  end
end
