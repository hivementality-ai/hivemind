# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ContextBudget do
  subject(:budget) { described_class.new(budget: 4000) }

  describe "#extract_signatures" do
    it "keeps class + method headers and drops method bodies" do
      src = <<~RUBY
        class Foo
          def bar
            x = 1
            y = x + 2
            y * 3
          end

          def baz(n)
            n.times.map { |i| i }
          end
        end
      RUBY

      sigs = budget.extract_signatures(src)

      expect(sigs).to include("class Foo")
      expect(sigs).to include("def bar")
      expect(sigs).to include("def baz(n)")
      expect(sigs).not_to include("x = 1")
      expect(sigs).not_to include("n.times.map")
    end

    it "keeps Rails-style declarations (has_many, validates, scope)" do
      src = <<~RUBY
        class User < ApplicationRecord
          has_many :posts
          validates :email, presence: true
          scope :active, -> { where(active: true) }

          def display_name
            name.upcase
          end
        end
      RUBY

      sigs = budget.extract_signatures(src)

      expect(sigs).to include("has_many :posts")
      expect(sigs).to include("validates :email")
      expect(sigs).to include("scope :active")
      expect(sigs).to include("def display_name")
      expect(sigs).not_to include("name.upcase")
    end
  end

  describe "#stats" do
    it "reports initial state before any load" do
      stats = budget.stats
      expect(stats[:budget]).to eq(4000)
      expect(stats[:tokens_used]).to eq(0)
      expect(stats[:full_files]).to eq(0)
      expect(stats[:signature_files]).to eq(0)
    end
  end

  describe "#load_for" do
    context "when the primary file can't be read" do
      before do
        allow(Tools::WorkspaceIo).to receive(:read_file).and_return(nil)
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(false)
      end

      it "returns an empty array" do
        expect(budget.load_for("/workspace/app/models/user.rb")).to eq([])
      end
    end

    context "when the primary file reads and has no related files" do
      before do
        allow(Tools::WorkspaceIo).to receive(:read_file).with("/workspace/app/models/user.rb").and_return("class User\nend\n")
        allow(Tools::WorkspaceIo).to receive(:file_exists?).and_return(false)
      end

      it "returns a single full-mode entry for the primary" do
        results = budget.load_for("/workspace/app/models/user.rb")
        expect(results).to eq([ { file: "/workspace/app/models/user.rb", content: "class User\nend\n", mode: :full } ])
        expect(budget.stats[:full_files]).to eq(1)
      end
    end
  end
end
