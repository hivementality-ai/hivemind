# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reflection::QualityScorer, type: :service do
  subject(:score) { described_class.score(reflection) }

  let(:strong_reflection) do
    {
      "went_well"       => [ "Matched existing patterns by reading nearby files first", "Tests passed without iteration" ],
      "was_hard"        => [ "Untangling the hook pipeline call order took significant effort" ],
      "do_differently"  => [ "Set up the worktree before reading any files to avoid confusion" ],
      "novel_solutions" => [ "Injecting the reflection trigger before hooks avoids timing races" ],
      "key_insights"    => [ "Always verify file permissions on worktree files before editing" ]
    }
  end

  let(:filler_reflection) do
    {
      "went_well"       => [ "Fine" ],
      "was_hard"        => [ "N/A" ],
      "do_differently"  => [ "Nothing" ],
      "novel_solutions" => [],
      "key_insights"    => [ "Good" ]
    }
  end

  let(:empty_reflection) { {} }

  describe ".score" do
    context "with a strong, specific reflection" do
      let(:reflection) { strong_reflection }

      it "returns a score above the quality threshold (0.4)" do
        expect(score).to be > 0.4
      end

      it "returns a score at most 1.0" do
        expect(score).to be <= 1.0
      end

      it "awards a bonus for novel_solutions" do
        with_novel    = described_class.score(strong_reflection)
        without_novel = described_class.score(strong_reflection.merge("novel_solutions" => []))
        expect(with_novel).to be > without_novel
      end
    end

    context "with a filler / generic reflection" do
      let(:reflection) { filler_reflection }

      it "returns a score below the quality threshold (0.4)" do
        expect(score).to be < 0.4
      end
    end

    context "with an empty reflection" do
      let(:reflection) { empty_reflection }

      it "returns exactly 0.0" do
        expect(score).to eq(0.0)
      end
    end

    context "with nil input" do
      let(:reflection) { nil }

      it "returns 0.0 without raising" do
        expect(score).to eq(0.0)
      end
    end

    context "when only some sections are filled" do
      let(:reflection) do
        {
          "went_well"      => [ "Followed existing conventions throughout" ],
          "was_hard"       => [],
          "do_differently" => [],
          "novel_solutions" => [],
          "key_insights"   => [ "Read the codebase before making any changes" ]
        }
      end

      it "returns a partial (mid-range) score" do
        expect(score).to be_between(0.1, 0.9)
      end
    end

    context "with very short items (< 3 words)" do
      let(:reflection) do
        {
          "went_well"      => [ "ok" ],
          "was_hard"       => [ "hard" ],
          "do_differently" => [ "more care" ],
          "novel_solutions" => [],
          "key_insights"   => [ "be careful" ]
        }
      end

      it "penalises short items heavily" do
        expect(score).to be < 0.4
      end
    end
  end
end
