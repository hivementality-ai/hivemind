# frozen_string_literal: true

require "rails_helper"

# Server-rendered mobile views — driven by rack_test (no JS) so they run without
# a real browser. Mobile detection keys off the User-Agent header.
RSpec.describe "Mobile UI", type: :system do
  let(:user) { create(:user, :admin) }

  IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " \
              "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  before do
    driven_by(:rack_test)
    Setting.set("setup_complete", "true")
    page.driver.header("User-Agent", IPHONE_UA)
    sign_in user
  end

  describe "tasks" do
    let!(:agent) { create(:agent, name: "Builder") }
    let!(:in_progress) { create(:task, title: "Ship the thing", status: "in_progress", assigned_to_agent: agent) }
    let!(:backlog)     { create(:task, title: "Someday maybe", status: "backlog") }
    let!(:done)        { create(:task, title: "Already finished", status: "done") }

    it "redirects a mobile user from /tasks to the mobile board" do
      visit "/tasks"
      expect(page).to have_current_path("/m/tasks")
    end

    it "shows tasks grouped by status" do
      visit "/m/tasks"
      expect(page).to have_content("In Progress")
      expect(page).to have_content("Ship the thing")
      expect(page).to have_content("Builder")
      expect(page).to have_content("Backlog")
      expect(page).to have_content("Someday maybe")
      expect(page).to have_content("Already finished")
    end

    it "exposes a Tasks tab in the bottom nav" do
      visit "/m/tasks"
      expect(page).to have_link("Tasks", href: "/m/tasks")
    end

    it "opens a task detail view" do
      visit "/m/tasks"
      click_link "Ship the thing"
      expect(page).to have_current_path("/m/tasks/#{in_progress.id}")
      expect(page).to have_content("In Progress")
      expect(page).to have_content("Builder")
    end

    it "shows an empty state when there are no tasks" do
      Task.delete_all
      visit "/m/tasks"
      expect(page).to have_content("No tasks yet")
    end
  end

  describe "activity feed" do
    it "surfaces currently running sub-agent tasks" do
      create(:sub_agent_task, :running, task: "Crunching the numbers")
      visit "/m/activity"
      expect(page).to have_content("Task running")
      expect(page).to have_content("Crunching the numbers")
    end
  end
end
