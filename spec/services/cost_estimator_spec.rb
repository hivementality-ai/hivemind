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

          # 1000 * 1500 + 500 * 7500 = 1,500,000 + 3,750,000 = 5,250,000 / 1,000,000 = 5.25
          expect(cost).to eq(5.25)
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

          # 5000 * 80 + 2000 * 400 = 400,000 + 800,000 = 1,200,000 / 1,000,000 = 1.2
          expect(cost).to eq(1.2)
        end
      end

      context 'GPT models' do
        it 'calculates cost correctly for gpt-5.2' do
          cost = described_class.estimate(
            model: "gpt-5.2",
            input_tokens: 1000,
            output_tokens: 1000
          )

          # 1000 * 200 + 1000 * 800 = 200,000 + 800,000 = 1,000,000 / 1,000,000 = 1.0
          expect(cost).to eq(1.0)
        end

        it 'calculates cost correctly for gpt-5.2-mini' do
          cost = described_class.estimate(
            model: "gpt-5.2-mini",
            input_tokens: 10000,
            output_tokens: 5000
          )

          # 10000 * 40 + 5000 * 160 = 400,000 + 800,000 = 1,200,000 / 1,000,000 = 1.2
          expect(cost).to eq(1.2)
        end

        it 'calculates cost correctly for gpt-5.2-nano' do
          cost = described_class.estimate(
            model: "gpt-5.2-nano",
            input_tokens: 50000,
            output_tokens: 25000
          )

          # 50000 * 10 + 25000 * 40 = 500,000 + 1,000,000 = 1,500,000 / 1,000,000 = 1.5
          expect(cost).to eq(1.5)
        end
      end

      context 'o-series models' do
        it 'calculates cost correctly for o3' do
          cost = described_class.estimate(
            model: "o3",
            input_tokens: 500,
            output_tokens: 200
          )

          # 500 * 1000 + 200 * 4000 = 500,000 + 800,000 = 1,300,000 / 1,000,000 = 1.3
          expect(cost).to eq(1.3)
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

    describe 'edge cases' do
      context 'with zero tokens' do
        it 'returns zero cost for zero input tokens' do
          cost = described_class.estimate(
            model: "claude-sonnet-4-5",
            input_tokens: 0,
            output_tokens: 1000
          )

          # 0 * 300 + 1000 * 1500 = 1,500,000 / 1,000,000 = 1.5
          expect(cost).to eq(1.5)
        end

        it 'returns zero cost for zero output tokens' do
          cost = described_class.estimate(
            model: "claude-sonnet-4-5",
            input_tokens: 1000,
            output_tokens: 0
          )

          # 1000 * 300 + 0 * 1500 = 300,000 / 1,000,000 = 0.3
          expect(cost).to eq(0.3)
        end

        it 'returns zero cost for both zero tokens' do
          cost = described_class.estimate(
            model: "claude-sonnet-4-5",
            input_tokens: 0,
            output_tokens: 0
          )

          expect(cost).to eq(0.0)
        end
      end

      context 'with very small token counts' do
        it 'handles fractional costs correctly' do
          cost = described_class.estimate(
            model: "claude-haiku-4-5",
            input_tokens: 1,
            output_tokens: 1
          )

          # 1 * 80 + 1 * 400 = 480 / 1,000,000 = 0.00048 -> rounded to 4 decimal places
          expect(cost).to eq(0.0005)
        end

        it 'rounds to 4 decimal places' do
          cost = described_class.estimate(
            model: "claude-haiku-4-5",
            input_tokens: 12,
            output_tokens: 34
          )

          # 12 * 80 + 34 * 400 = 960 + 13600 = 14560 / 1,000,000 = 0.01456
          expect(cost).to eq(0.0146)
        end
      end

      context 'with very large token counts' do
        it 'handles large numbers correctly' do
          cost = described_class.estimate(
            model: "claude-opus-4-6",
            input_tokens: 1_000_000,
            output_tokens: 500_000
          )

          # 1M * 1500 + 500K * 7500 = 1.5B + 3.75B = 5.25B / 1M = 5250.0
          expect(cost).to eq(5250.0)
        end
      end
    end

    describe 'rate consistency' do
      it 'maintains consistent rate structure for all models' do
        CostEstimator::RATES.each do |model, rates|
          expect(rates).to have_key(:input)
          expect(rates).to have_key(:output)
          expect(rates[:input]).to be_a(Integer)
          expect(rates[:output]).to be_a(Integer)
          expect(rates[:input]).to be > 0
          expect(rates[:output]).to be > 0
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

      it 'opus is most expensive' do
        opus_cost = described_class.estimate(model: "claude-opus-4-6", **token_counts)
        sonnet_cost = described_class.estimate(model: "claude-sonnet-4-5", **token_counts)
        haiku_cost = described_class.estimate(model: "claude-haiku-4-5", **token_counts)

        expect(opus_cost).to be > sonnet_cost
        expect(sonnet_cost).to be > haiku_cost
      end

      it 'nano is cheapest among gpt models' do
        regular_cost = described_class.estimate(model: "gpt-5.2", **token_counts)
        mini_cost = described_class.estimate(model: "gpt-5.2-mini", **token_counts)
        nano_cost = described_class.estimate(model: "gpt-5.2-nano", **token_counts)

        expect(regular_cost).to be > mini_cost
        expect(mini_cost).to be > nano_cost
      end

      it 'o3 is more expensive than o4-mini' do
        o3_cost = described_class.estimate(model: "o3", **token_counts)
        o4_mini_cost = described_class.estimate(model: "o4-mini", **token_counts)

        expect(o3_cost).to be > o4_mini_cost
      end
    end
  end
end