# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::BudgetLimitsValidator do
  def call(budget_limits)
    described_class.call(budget_limits: budget_limits)
  end

  describe "nil / blank input" do
    it "succeeds on nil" do
      expect(call(nil)).to be_success
    end

    it "succeeds on empty hash" do
      expect(call({})).to be_success
    end
  end

  describe "type check" do
    it "fails when budget_limits is not a hash" do
      result = call("10.0")
      expect(result).to be_error
      expect(result.payload[:errors]).to include("budget_limits must be an object")
    end
  end

  describe "daily_limit" do
    it "succeeds with a positive float" do
      expect(call({ "daily_limit" => 25.0 })).to be_success
    end

    it "succeeds with a positive integer" do
      expect(call({ "daily_limit" => 10 })).to be_success
    end

    it "fails when daily_limit is zero" do
      result = call({ "daily_limit" => 0 })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/daily_limit.*positive number/)
    end

    it "fails when daily_limit is negative" do
      result = call({ "daily_limit" => -5.0 })
      expect(result).to be_error
    end

    it "fails when daily_limit is a string" do
      result = call({ "daily_limit" => "ten" })
      expect(result).to be_error
    end
  end

  describe "monthly_limit" do
    it "succeeds with a positive float" do
      expect(call({ "monthly_limit" => 200.0 })).to be_success
    end

    it "fails when monthly_limit is zero" do
      result = call({ "monthly_limit" => 0 })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/monthly_limit.*positive number/)
    end
  end

  describe "periods" do
    it "succeeds with valid period entries" do
      result = call({
        "periods" => [
          { "period" => "daily",   "limit_cents" => 1000 },
          { "period" => "weekly",  "limit_cents" => 5000 },
          { "period" => "monthly", "limit_cents" => 20000 }
        ]
      })
      expect(result).to be_success
    end

    it "fails when periods is not an array" do
      result = call({ "periods" => { "daily" => 1000 } })
      expect(result).to be_error
      expect(result.payload[:errors]).to include("budget_limits.periods must be an array")
    end

    it "fails when a period entry is not a hash" do
      result = call({ "periods" => ["daily"] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/periods\[0\].*object/)
    end

    it "fails when period is missing" do
      result = call({ "periods" => [{ "limit_cents" => 1000 }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/periods\[0\]\.period.*required/)
    end

    it "fails when period is invalid" do
      result = call({ "periods" => [{ "period" => "quarterly", "limit_cents" => 1000 }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/quarterly.*invalid/)
    end

    it "fails when limit_cents is missing" do
      result = call({ "periods" => [{ "period" => "daily" }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/limit_cents.*required/)
    end

    it "fails when limit_cents is zero" do
      result = call({ "periods" => [{ "period" => "daily", "limit_cents" => 0 }] })
      expect(result).to be_error
      expect(result.payload[:errors].first).to match(/limit_cents.*positive integer/)
    end

    it "fails when limit_cents is a float" do
      result = call({ "periods" => [{ "period" => "daily", "limit_cents" => 10.5 }] })
      expect(result).to be_error
    end

    it "collects errors across multiple invalid entries" do
      result = call({
        "periods" => [
          { "period" => "bad",   "limit_cents" => 0 },
          { "period" => "daily", "limit_cents" => 100 }
        ]
      })
      expect(result).to be_error
      expect(result.payload[:errors].size).to be >= 2
    end
  end
end
