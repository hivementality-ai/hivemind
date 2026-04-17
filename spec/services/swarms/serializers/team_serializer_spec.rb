# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::TeamSerializer do
  describe ".call" do
    context "when team is nil" do
      it "returns nil" do
        expect(described_class.call(team: nil)).to be_nil
      end
    end

    context "when team has no name" do
      it "returns nil" do
        team = build(:team, name: nil)
        expect(described_class.call(team: team)).to be_nil
      end
    end

    context "with a team that has a name" do
      it "includes name" do
        team = build(:team, name: "Ops Squad")
        result = described_class.call(team: team)
        expect(result["name"]).to eq("Ops Squad")
      end

      it "includes description when present" do
        team = build(:team, name: "Ops", description: "Handles operations")
        result = described_class.call(team: team)
        expect(result["description"]).to eq("Handles operations")
      end

      it "omits description when blank" do
        team = build(:team, name: "Ops", description: nil)
        result = described_class.call(team: team)
        expect(result).not_to have_key("description")
      end

      it "includes custom_soul when present" do
        team = build(:team, name: "Ops", custom_soul: "You are an elite ops team.")
        result = described_class.call(team: team)
        expect(result["custom_soul"]).to eq("You are an elite ops team.")
      end

      it "omits custom_soul when blank" do
        team = build(:team, name: "Ops", custom_soul: nil)
        result = described_class.call(team: team)
        expect(result).not_to have_key("custom_soul")
      end

      it "returns a Hash" do
        team = build(:team, name: "Ops")
        expect(described_class.call(team: team)).to be_a(Hash)
      end
    end
  end
end
