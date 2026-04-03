# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent, type: :model do
  describe "hierarchy" do
    let!(:alpha) { create(:agent, name: "Alpha") }
    let!(:beta)  { create(:agent, name: "Beta",  reports_to_id: alpha.id) }
    let!(:gamma) { create(:agent, name: "Gamma", reports_to_id: alpha.id) }
    let!(:delta) { create(:agent, name: "Delta", reports_to_id: beta.id) }

    describe "associations" do
      it "resolves manager via belongs_to" do
        expect(beta.manager).to eq(alpha)
      end

      it "resolves direct_reports via has_many" do
        expect(alpha.direct_reports).to contain_exactly(beta, gamma)
      end

      it "accepts nil manager (root node)" do
        expect(alpha.manager).to be_nil
      end
    end

    describe "validations" do
      describe "no self-reporting" do
        it "is invalid when reports_to_id equals own id" do
          alpha.reports_to_id = alpha.id
          expect(alpha).not_to be_valid
          expect(alpha.errors[:reports_to_id]).to include("cannot report to self")
        end

        it "is valid when reports_to_id is nil" do
          expect(alpha).to be_valid
        end
      end

      describe "cycle detection" do
        it "is invalid when a cycle would be created (A -> B -> A)" do
          # alpha already has beta reporting to it; alpha reporting to beta = cycle
          alpha.reports_to_id = beta.id
          expect(alpha).not_to be_valid
          expect(alpha.errors[:reports_to_id]).to include("would create a reporting cycle")
        end

        it "is invalid for a three-node cycle (A -> B -> C -> A)" do
          # alpha -> beta -> delta; now make alpha report to delta
          alpha.reports_to_id = delta.id
          expect(alpha).not_to be_valid
          expect(alpha.errors[:reports_to_id]).to include("would create a reporting cycle")
        end

        it "is valid when reporting to an unrelated agent" do
          orphan = create(:agent, name: "Orphan")
          beta.reports_to_id = orphan.id
          expect(beta).to be_valid
        end
      end
    end

    describe "#chain_of_command" do
      it "returns ordered managers from immediate up to root" do
        expect(delta.chain_of_command).to eq([beta, alpha])
      end

      it "returns empty array for a root agent" do
        expect(alpha.chain_of_command).to eq([])
      end

      it "returns single-element array for a direct report of root" do
        expect(beta.chain_of_command).to eq([alpha])
      end
    end

    describe "#org_subtree" do
      it "returns all descendants of a node" do
        expect(alpha.org_subtree).to contain_exactly(beta, gamma, delta)
      end

      it "returns only direct reports when no grandchildren" do
        expect(beta.org_subtree).to contain_exactly(delta)
      end

      it "returns empty array for a leaf node" do
        expect(delta.org_subtree).to be_empty
      end
    end

    describe "#peers" do
      it "returns sibling agents sharing the same manager" do
        expect(beta.peers).to contain_exactly(gamma)
      end

      it "excludes self from peers" do
        expect(beta.peers).not_to include(beta)
      end

      it "returns empty relation for a root node with no manager" do
        expect(alpha.peers).to be_empty
      end
    end

    describe "#root?" do
      it "is true for an agent with no manager" do
        expect(alpha.root?).to be true
      end

      it "is false for an agent with a manager" do
        expect(beta.root?).to be false
      end
    end

    describe "#leaf?" do
      it "is true for an agent with no direct reports" do
        expect(delta.leaf?).to be true
      end

      it "is false for an agent with direct reports" do
        expect(alpha.leaf?).to be false
      end
    end

    describe "on_delete nullify" do
      it "nullifies reports_to_id on direct reports when manager is destroyed" do
        beta.reload
        expect(beta.reports_to_id).to eq(alpha.id)

        alpha.destroy!

        expect(beta.reload.reports_to_id).to be_nil
        expect(gamma.reload.reports_to_id).to be_nil
      end

      it "does not destroy the direct reports themselves" do
        alpha.destroy!
        expect(Agent.exists?(beta.id)).to be true
        expect(Agent.exists?(gamma.id)).to be true
      end
    end

    describe "title field" do
      it "persists a title on the agent" do
        alpha.update!(title: "Chief Executive")
        expect(alpha.reload.title).to eq("Chief Executive")
      end

      it "allows title to be nil" do
        alpha.update!(title: nil)
        expect(alpha.reload.title).to be_nil
      end

      it "is valid as a root node with a title but no manager" do
        agent = build(:agent, title: "Founder", reports_to_id: nil)
        expect(agent).to be_valid
      end
    end

    describe "#chain_of_command with deep hierarchy" do
      it "returns all ancestors in order without looping for a 4-level chain" do
        epsilon = create(:agent, name: "Epsilon", reports_to_id: delta.id)
        # chain: epsilon -> delta -> beta -> alpha
        expect(epsilon.chain_of_command).to eq([delta, beta, alpha])
      end
    end

    describe "manager reassignment" do
      it "removes the report from the old manager and adds to the new one" do
        new_manager = create(:agent, name: "NewManager")

        beta.update!(reports_to_id: new_manager.id)

        expect(alpha.reload.direct_reports).not_to include(beta)
        expect(new_manager.reload.direct_reports).to include(beta)
      end
    end
  end
end
