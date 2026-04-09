# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ProjectStatusExecutor do
  describe "#call" do
    let(:team) { create(:team) }
    let(:user) { create(:user) }
    let(:agent) { create(:agent, team: team) }

    context "when project_id is given" do
      it "returns the specific project" do
        project = create(:project, team: team, user: user, title: "My Project")
        executor = described_class.new(input: { "project_id" => project.id }, agent: agent)

        result = executor.call

        expect(result).to be_success
        expect(result.data[:output]).to include("My Project")
      end

      it "returns failure for non-existent project_id" do
        executor = described_class.new(input: { "project_id" => 99999 }, agent: agent)

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("project_list")
      end
    end

    context "when no project_id is given and no session metadata" do
      it "returns failure pointing to project_list" do
        executor = described_class.new(input: {}, agent: agent)

        result = executor.call

        expect(result).not_to be_success
        expect(result.error).to include("project_list")
      end
    end
  end
end
