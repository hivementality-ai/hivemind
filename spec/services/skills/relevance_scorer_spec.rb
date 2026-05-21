# frozen_string_literal: true

require "rails_helper"

RSpec.describe Skills::RelevanceScorer, type: :service do
  def build_skill(tags: [], trigger_patterns: [])
    build(:skill, tags: tags, trigger_patterns: trigger_patterns)
  end

  describe ".score" do
    context "when skill has no tags or patterns" do
      it "returns 0.0" do
        skill = build_skill
        expect(described_class.score(skill: skill, context: "open a PR on github")).to eq(0.0)
      end
    end

    context "when context is blank" do
      it "returns 0.0" do
        skill = build_skill(tags: %w[github])
        expect(described_class.score(skill: skill, context: "")).to eq(0.0)
      end
    end

    context "with tag matching" do
      it "scores one matching tag" do
        skill = build_skill(tags: %w[github])
        score = described_class.score(skill: skill, context: "I need to open a PR on github")
        expect(score).to eq(0.25)
      end

      it "compounds multiple matching tags up to 1.0" do
        skill = build_skill(tags: %w[github pr commit])
        score = described_class.score(skill: skill, context: "I need to open a pr on github after I commit")
        expect(score).to be_within(0.001).of(0.75)
      end

      it "is case insensitive" do
        skill = build_skill(tags: %w[GitHub])
        score = described_class.score(skill: skill, context: "check github ci")
        expect(score).to eq(0.25)
      end

      it "scores 0.0 when no tags match" do
        skill = build_skill(tags: %w[docker container])
        score = described_class.score(skill: skill, context: "check github ci")
        expect(score).to eq(0.0)
      end
    end

    context "with trigger pattern matching" do
      it "scores a matching pattern" do
        skill = build_skill(trigger_patterns: ["open.*pr"])
        score = described_class.score(skill: skill, context: "please open a PR for me")
        expect(score).to eq(0.5)
      end

      it "compounds multiple matching patterns" do
        skill = build_skill(trigger_patterns: ["open.*pr", "create.*pull.?request"])
        score = described_class.score(skill: skill, context: "open a pr by creating a pull request")
        expect(score).to be_within(0.001).of(1.0)
      end

      it "skips invalid regex without raising" do
        skill = build_skill(trigger_patterns: ["[invalid", "github"])
        expect { described_class.score(skill: skill, context: "check github") }.not_to raise_error
      end
    end

    context "with combined tags and patterns" do
      it "adds tag and pattern scores, capped at 1.0" do
        skill = build_skill(tags: %w[github], trigger_patterns: ["open.*pr", "check.*ci", "push.*branch"])
        score = described_class.score(skill: skill, context: "open a pr on github and push branch then check ci")
        expect(score).to eq(1.0)
      end
    end
  end

  describe ".rank" do
    let(:github_skill) do
      build_skill(tags: %w[github pr], trigger_patterns: ["open.*pr"])
    end

    let(:docker_skill) do
      build_skill(tags: %w[docker container], trigger_patterns: ["docker.*run"])
    end

    let(:weather_skill) do
      build_skill(tags: %w[weather forecast], trigger_patterns: ["what.*weather"])
    end

    context "when context is blank" do
      it "returns empty array" do
        result = described_class.rank(skills: [github_skill], context: "")
        expect(result).to be_empty
      end
    end

    it "returns skills above the threshold, sorted by score descending" do
      context_text = "open a pr on github"
      result = described_class.rank(
        skills: [github_skill, docker_skill, weather_skill],
        context: context_text,
        threshold: 0.3
      )

      expect(result.map { |r| r[:skill] }).to include(github_skill)
      expect(result.map { |r| r[:skill] }).not_to include(docker_skill)
      expect(result.map { |r| r[:skill] }).not_to include(weather_skill)
      expect(result.first[:score]).to be >= result.last[:score] if result.size > 1
    end

    it "filters out skills below threshold" do
      result = described_class.rank(
        skills: [github_skill, docker_skill],
        context: "open a pr on github",
        threshold: 0.9
      )
      # docker_skill shouldn't score high on a github context
      docker_result = result.find { |r| r[:skill] == docker_skill }
      expect(docker_result).to be_nil
    end
  end
end
