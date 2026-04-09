# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ProjectListExecutor do
  describe "#call" do
    let(:team) { create(:team) }
    let(:user) { create(:user) }
    let(:agent) { create(:agent, team: team) }

    context "when team has projects" do
      it "lists all visible projects" do
        p1 = create(:project, team: team, user: user, title: "Content Campaign")
        p2 = create(:project, :active, team: team, user: user, title: "Product Launch")

        executor = described_class.new(input: {}, agent: agent)
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("Content Campaign")
        expect(result.data[:output]).to include("Product Launch")
        expect(result.data[:output]).to include("[ID:#{p1.id}]")
        expect(result.data[:output]).to include("[ID:#{p2.id}]")
      end

      it "excludes archived projects" do
        create(:project, team: team, user: user, title: "Old Project", status: "archived")
        create(:project, :active, team: team, user: user, title: "Active Project")

        executor = described_class.new(input: {}, agent: agent)
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("Active Project")
        expect(result.data[:output]).not_to include("Old Project")
      end

      it "filters by status when provided" do
        create(:project, team: team, user: user, title: "Planning One")
        create(:project, :active, team: team, user: user, title: "Active One")

        executor = described_class.new(input: { "status" => "active" }, agent: agent)
        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("Active One")
        expect(result.data[:output]).not_to include("Planning One")
      end
    end

    context "when team has no projects" do
      it "returns failure with guidance" do
        executor = described_class.new(input: {}, agent: agent)
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("No projects found")
        expect(result.error).to include("project_create")
      end
    end

    context "when agent has no team" do
      it "returns failure" do
        teamless_agent = create(:agent, team: nil)
        executor = described_class.new(input: {}, agent: teamless_agent)
        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("must belong to a team")
      end
    end
  end
end
