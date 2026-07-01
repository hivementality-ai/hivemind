# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::ProposalValidator, type: :service do
  let(:valid_content) do
    <<~MD
      ## Overview

      This skill teaches the agent how to interact with the GitHub API using the gh CLI.
      It covers authentication, creating pull requests, and checking CI status.

      ## Usage

      Load this skill when working on GitHub-hosted repositories.
    MD
  end

  def call(overrides = {})
    described_class.call(
      name: overrides.fetch(:name, "my_skill"),
      summary: overrides.fetch(:summary, "A useful skill that does something helpful"),
      content: overrides.fetch(:content, valid_content),
      category: overrides.fetch(:category, "coding")
    )
  end

  describe ".call" do
    context "with valid inputs" do
      it "returns success" do
        expect(call).to be_success
      end
    end

    context "name validation" do
      it "rejects blank name" do
        result = call(name: "")
        expect(result).not_to be_success
        expect(result.error).to include("Name is required")
      end

      it "rejects names longer than 60 characters" do
        result = call(name: "a" * 61)
        expect(result).not_to be_success
        expect(result.error).to include("60 characters")
      end

      it "rejects names with uppercase letters" do
        result = call(name: "MySkill")
        expect(result).not_to be_success
        expect(result.error).to include("lowercase")
      end

      it "rejects names with spaces" do
        result = call(name: "my skill")
        expect(result).not_to be_success
        expect(result.error).to include("lowercase")
      end

      it "accepts snake_case names" do
        expect(call(name: "my_skill")).to be_success
      end

      it "accepts hyphenated names" do
        expect(call(name: "my-skill")).to be_success
      end

      it "accepts names with numbers" do
        expect(call(name: "skill2")).to be_success
      end
    end

    context "summary validation" do
      it "rejects blank summary" do
        result = call(summary: "")
        expect(result).not_to be_success
        expect(result.error).to include("Summary is required")
      end

      it "rejects summary over 150 chars" do
        result = call(summary: "x" * 151)
        expect(result).not_to be_success
        expect(result.error).to include("150 characters")
      end

      it "accepts summary at exactly 150 chars" do
        expect(call(summary: "x" * 150)).to be_success
      end
    end

    context "content length" do
      it "rejects content under 200 chars" do
        result = call(content: "## Hi\n\nToo short.")
        expect(result).not_to be_success
        expect(result.error).to include("200 characters")
        expect(result.error).to include("got")
      end

      it "accepts content at exactly 200 chars padded with a heading" do
        padding = "x" * (200 - "## H\n\n".length)
        content = "## H\n\n" + padding
        expect(call(content: content)).to be_success
      end
    end

    context "content structure" do
      it "rejects content with no ## heading" do
        content = "a" * 300  # long enough but no headings
        result = call(content: content)
        expect(result).not_to be_success
        expect(result.error).to include("section heading")
      end

      it "accepts content with a ## heading" do
        expect(call(content: valid_content)).to be_success
      end
    end

    context "category validation" do
      it "accepts a blank category (defaults to utilities in SkillCreator)" do
        expect(call(category: "")).to be_success
      end

      it "accepts all known categories" do
        Skill::CATEGORIES.each do |cat|
          expect(call(category: cat)).to be_success
        end
      end

      it "accepts unknown categories (SkillCreator#resolve_category handles defaulting)" do
        # ProposalValidator does not gatekeep category — unknown values fall
        # through to SkillCreator#resolve_category which defaults to "utilities".
        expect(call(category: "nonsense_category")).to be_success
      end
    end

    context "sensitive data detection" do
      it "rejects content containing an API key pattern" do
        result = call(content: valid_content + "\napi_key: abc123secretvalue")
        expect(result).not_to be_success
        expect(result.error).to include("sensitive data")
      end

      it "rejects content containing a GitHub PAT" do
        result = call(content: valid_content + "\nghp_abcdefghijklmnopqrstuvwxyz1234567890")
        expect(result).not_to be_success
        expect(result.error).to include("sensitive data")
      end

      it "rejects content containing an OpenAI key" do
        result = call(content: valid_content + "\nsk-abcdefghijklmnopqrstuvwxyzABCDEFGH")
        expect(result).not_to be_success
        expect(result.error).to include("sensitive data")
      end

      it "does not reject content that merely mentions 'api_key' as a concept" do
        safe_content = valid_content + "\n\nYou can configure the api_key via your environment variables."
        # This doesn't match the pattern (no = or : followed by a value)
        expect(call(content: safe_content)).to be_success
      end
    end

    context "multiple errors" do
      it "reports all errors together" do
        result = call(name: "", summary: "", content: "x")
        expect(result).not_to be_success
        # Multiple failures reported in one error string
        expect(result.error).to include("Name is required")
        expect(result.error).to include("Summary is required")
        expect(result.error).to include("200 characters")
      end
    end
  end
end
