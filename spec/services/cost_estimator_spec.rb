# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CostEstimator do
  describe '.estimate' do
    describe 'with known models' do
      context 'Claude Opus' do
        it 'calculates cost correctly for claude-opus-4-6' do
          cost = described_class.estimate(
            model: "claude-opus-4-6",
            input_tokens: 1000,
            output_tokens: 500
          )

          # 1000 * 500 + 500 * 2500 = 500,000 + 1,250,000 = 1,750,000 / 1,000,000 = 1.75
          expect(cost).to eq(1.75)
        end
      end

      context 'Claude Sonnet' do
        it 'calculates cost correctly for claude-sonnet-4-5' do
          cost = described_class.estimate(
            model: "claude-sonnet-4-5",
            input_tokens: 2000,
            output_tokens: 1000
          )

          # 2000 * 300 + 1000 * 1500 = 600,000 + 1,500,000 = 2,100,000 / 1,000,000 = 2.1
          expect(cost).to eq(2.1)
        end
      end

      context 'Claude Haiku' do
        it 'calculates cost correctly for claude-haiku-4-5' do
          cost = described_class.estimate(
            model: "claude-haiku-4-5",
            input_tokens: 5000,
            output_tokens: 2000
          )

          # 5000 * 100 + 2000 * 500 = 500,000 + 1,000,000 = 1,500,000 / 1,000,000 = 1.5
          expect(cost).to eq(1.5)
        end
      end

      context 'GPT models' do
        it 'calculates cost correctly for gpt-5.2' do
          cost = described_class.estimate(
            model: "gpt-5.2",
            input_tokens: 1000,
            output_tokens: 1000
          )

          # 1000 * 175 + 1000 * 1400 = 175,000 + 1,400,000 = 1,575,000 / 1,000,000 = 1.575
          expect(cost).to eq(1.575)
        end

        it 'calculates cost correctly for gpt-5-mini' do
          cost = described_class.estimate(
            model: "gpt-5-mini",
            input_tokens: 10000,
            output_tokens: 5000
          )

          # 10000 * 25 + 5000 * 200 = 250,000 + 1,000,000 = 1,250,000 / 1,000,000 = 1.25
          expect(cost).to eq(1.25)
        end

        it 'calculates cost correctly for gpt-5-nano' do
          cost = described_class.estimate(
            model: "gpt-5-nano",
            input_tokens: 50000,
            output_tokens: 25000
          )

          # 50000 * 5 + 25000 * 40 = 250,000 + 1,000,000 = 1,250,000 / 1,000,000 = 1.25
          expect(cost).to eq(1.25)
        end
      end

      context 'o-series models' do
        it 'calculates cost correctly for o3' do
          cost = described_class.estimate(
            model: "o3",
            input_tokens: 500,
            output_tokens: 200
          )

          # 500 * 200 + 200 * 800 = 100,000 + 160,000 = 260,000 / 1,000,000 = 0.26
          expect(cost).to eq(0.26)
        end

        it 'calculates cost correctly for o4-mini' do
          cost = described_class.estimate(
            model: "o4-mini",
            input_tokens: 2000,
            output_tokens: 1500
          )

          # 2000 * 110 + 1500 * 440 = 220,000 + 660,000 = 880,000 / 1,000,000 = 0.88
          expect(cost).to eq(0.88)
        end
      end
    end

    describe 'with unknown model' do
      it 'uses default rates for unknown models' do
        cost = described_class.estimate(
          model: "unknown-model",
          input_tokens: 1000,
          output_tokens: 500
        )

        # Using default rates: input: 100, output: 400
        # 1000 * 100 + 500 * 400 = 100,000 + 200,000 = 300,000 / 1,000,000 = 0.3
        expect(cost).to eq(0.3)
      end

      it 'uses default rates for nil model' do
        cost = described_class.estimate(
          model: nil,
          input_tokens: 2000,
          output_tokens: 1000
        )

        # 2000 * 100 + 1000 * 400 = 200,000 + 400,000 = 600,000 / 1,000,000 = 0.6
        expect(cost).to eq(0.6)
      end
    end

    describe 'with model variants' do
      it 'matches model variants via prefix' do
        cost = described_class.estimate(
          model: "claude-sonnet-4-5-20250101",
          input_tokens: 1000,
          output_tokens: 500
        )

        expected = described_class.estimate(
          model: "claude-sonnet-4-5",
          input_tokens: 1000,
          output_tokens: 500
        )

        expect(cost).to eq(expected)
      end
    end

    describe 'with local models' do
      it 'returns zero for ollama models' do
        cost = described_class.estimate(model: "ollama", input_tokens: 10000, output_tokens: 5000)
        expect(cost).to eq(0.0)
      end

      it 'returns zero for llama models' do
        cost = described_class.estimate(model: "llama3.2:3b", input_tokens: 10000, output_tokens: 5000)
        expect(cost).to eq(0.0)
      end

      it 'returns zero for mistral models' do
        cost = described_class.estimate(model: "mistral-7b", input_tokens: 10000, output_tokens: 5000)
        expect(cost).to eq(0.0)
      end
    end

    describe 'edge cases' do
      context 'with zero tokens' do
        it 'returns zero cost for zero input tokens' do
          cost = described_class.estimate(model: "claude-sonnet-4-5", input_tokens: 0, output_tokens: 1000)
          expect(cost).to eq(1.5)
        end

        it 'returns zero cost for zero output tokens' do
          cost = described_class.estimate(model: "claude-sonnet-4-5", input_tokens: 1000, output_tokens: 0)
          expect(cost).to eq(0.3)
        end

        it 'returns zero cost for both zero tokens' do
          cost = described_class.estimate(model: "claude-sonnet-4-5", input_tokens: 0, output_tokens: 0)
          expect(cost).to eq(0.0)
        end
      end

      context 'with very small token counts' do
        it 'handles fractional costs correctly' do
          cost = described_class.estimate(model: "claude-haiku-4-5", input_tokens: 1, output_tokens: 1)
          # 1 * 100 + 1 * 500 = 600 / 1,000,000 = 0.0006
          expect(cost).to eq(0.0006)
        end

        it 'rounds to 4 decimal places' do
          cost = described_class.estimate(model: "claude-haiku-4-5", input_tokens: 12, output_tokens: 34)
          # 12 * 100 + 34 * 500 = 1200 + 17000 = 18200 / 1,000,000 = 0.0182
          expect(cost).to eq(0.0182)
        end
      end

      context 'with very large token counts' do
        it 'handles large numbers correctly' do
          cost = described_class.estimate(model: "claude-opus-4-6", input_tokens: 1_000_000, output_tokens: 500_000)
          # 1M * 500 + 500K * 2500 = 500M + 1.25B = 1.75B / 1M = 1750.0
          expect(cost).to eq(1750.0)
        end
      end
    end

    describe 'rate consistency' do
      it 'maintains consistent rate structure for all models' do
        CostEstimator::RATES.each do |model, rates|
          expect(rates).to have_key(:input), "#{model} missing :input"
          expect(rates).to have_key(:output), "#{model} missing :output"
          expect(rates[:input]).to be_a(Integer), "#{model} input not Integer"
          expect(rates[:output]).to be_a(Integer), "#{model} output not Integer"
          expect(rates[:input]).to be >= 0, "#{model} input negative"
          expect(rates[:output]).to be >= 0, "#{model} output negative"
        end
      end

      it 'has default rate with correct structure' do
        default = CostEstimator::DEFAULT_RATE
        expect(default).to have_key(:input)
        expect(default).to have_key(:output)
        expect(default[:input]).to eq(100)
        expect(default[:output]).to eq(400)
      end
    end

    describe 'cost comparisons' do
      let(:token_counts) { { input_tokens: 1000, output_tokens: 500 } }

      it 'opus is most expensive Claude model' do
        opus_cost = described_class.estimate(model: "claude-opus-4-6", **token_counts)
        sonnet_cost = described_class.estimate(model: "claude-sonnet-4-5", **token_counts)
        haiku_cost = described_class.estimate(model: "claude-haiku-4-5", **token_counts)

        expect(opus_cost).to be > sonnet_cost
        expect(sonnet_cost).to be > haiku_cost
      end

      it 'nano is cheapest among gpt-5 models' do
        regular_cost = described_class.estimate(model: "gpt-5.2", **token_counts)
        nano_cost = described_class.estimate(model: "gpt-5-nano", **token_counts)

        expect(regular_cost).to be > nano_cost
      end

      it 'o3 is more expensive than o4-mini' do
        o3_cost = described_class.estimate(model: "o3", **token_counts)
        o4_mini_cost = described_class.estimate(model: "o4-mini", **token_counts)

        expect(o3_cost).to be > o4_mini_cost
      end
    end
  end

  describe '.breakdown' do
    it 'returns input, output, and total cost' do
      result = described_class.breakdown(model: "claude-opus-4-6", input_tokens: 1000, output_tokens: 500)

      expect(result).to have_key(:input_cost_cents)
      expect(result).to have_key(:output_cost_cents)
      expect(result).to have_key(:total_cost_cents)
      expect(result[:total_cost_cents]).to eq(result[:input_cost_cents] + result[:output_cost_cents])
    end

    it 'matches estimate total' do
      estimate = described_class.estimate(model: "claude-opus-4-6", input_tokens: 1000, output_tokens: 500)
      breakdown = described_class.breakdown(model: "claude-opus-4-6", input_tokens: 1000, output_tokens: 500)

      expect(breakdown[:total_cost_cents]).to eq(estimate)
    end
  end

  describe '.find_rate' do
    it 'returns exact match' do
      expect(described_class.find_rate("claude-opus-4-6")).to eq({ input: 500, output: 2500 })
    end

    it 'returns default for unknown model' do
      expect(described_class.find_rate("totally-unknown")).to eq(CostEstimator::DEFAULT_RATE)
    end

    it 'returns ollama rate for nil' do
      expect(described_class.find_rate(nil)).to eq(CostEstimator::DEFAULT_RATE)
    end
  end
end
