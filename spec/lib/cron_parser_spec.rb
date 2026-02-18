# frozen_string_literal: true

require "rails_helper"

RSpec.describe CronParser do
  describe ".parse" do
    it "parses every 5 minutes" do
      result = CronParser.parse("*/5 * * * *")
      expect(result).to eq("Every 5 minutes")
    end

    it "parses every 30 minutes" do
      result = CronParser.parse("*/30 * * * *")
      expect(result).to eq("Every 30 minutes")
    end

    it "parses daily at specific time" do
      result = CronParser.parse("0 9 * * *")
      expect(result).to eq("Daily at 09:00")
    end

    it "parses daily at midnight" do
      result = CronParser.parse("0 0 * * *")
      expect(result).to eq("Daily at 00:00")
    end

    it "parses Monday at 9 AM" do
      result = CronParser.parse("0 9 * * 1")
      expect(result).to eq("Every Monday at 09:00")
    end

    it "parses multiple days (Monday and Friday)" do
      result = CronParser.parse("0 9 * * 1,5")
      expect(result).to include("Monday")
      expect(result).to include("Friday")
      expect(result).to include("09:00")
    end

    it "parses every hour" do
      result = CronParser.parse("0 * * * *")
      expect(result).to eq("Every hour")
    end

    it "parses monthly on day 1" do
      result = CronParser.parse("0 9 1 * *")
      expect(result).to eq("Monthly on day 1 at 09:00")
    end

    it "parses monthly on day 15" do
      result = CronParser.parse("0 14 15 * *")
      expect(result).to eq("Monthly on day 15 at 14:00")
    end

    it "handles malformed expressions gracefully" do
      result = CronParser.parse("invalid")
      expect(result).to include("Custom schedule")
    end

    it "handles empty expression" do
      result = CronParser.parse("")
      expect(result).to include("Custom schedule")
    end

    it "handles only whitespace" do
      result = CronParser.parse("   ")
      expect(result).to include("Custom schedule")
    end

    it "parses with extra whitespace" do
      result = CronParser.parse("  0  9  *  *  1  ")
      expect(result).to eq("Every Monday at 09:00")
    end
  end

  describe "#to_human" do
    it "works with instance method" do
      parser = CronParser.new("0 9 * * 1")
      expect(parser.to_human).to eq("Every Monday at 09:00")
    end
  end
end
