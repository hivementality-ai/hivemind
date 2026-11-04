# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent templates index", type: :request do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  it "renders a heading with a count per category and every template" do
    coding = create_list(:agent_template, 2, category: "coding")
    research = create(:agent_template, category: "research", name: "Zed Researcher", description: "digs deep")

    get agent_templates_path

    expect(response).to be_successful
    expect(response.body).to include("Coding").and include("(2)")
    expect(response.body).to include("Research").and include("(1)")
    (coding + [ research ]).each do |t|
      expect(response.body).to include(t.name)
      expect(response.body).to include(agent_template_path(t))
    end
  end

  it "renders a search box wired to the filter controller with searchable text on each card" do
    create(:agent_template, name: "Zed Researcher", description: "Digs Deep")

    get agent_templates_path

    expect(response.body).to include('data-controller="template-filter"')
    expect(response.body).to include('data-action="input->template-filter#filter"')
    expect(response.body).to include('data-search-text="zed researcher digs deep"')
  end
end
