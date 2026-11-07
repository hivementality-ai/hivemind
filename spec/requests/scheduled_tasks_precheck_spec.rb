# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ScheduledTasks watch URL", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:task) { create(:scheduled_task, precheck_url: "https://example.com/feed.xml") }

  before { sign_in owner }

  it "shows the field on the edit form" do
    get edit_scheduled_task_path(task)
    expect(response.body).to include("Only run when this page or feed changes", "https://example.com/feed.xml")
  end

  it "saves the URL" do
    patch scheduled_task_path(task), params: { scheduled_task: { precheck_url: "https://example.com/new.xml" } }
    expect(task.reload.precheck_url).to eq("https://example.com/new.xml")
  end

  it "shows when a check found nothing new" do
    task.update!(last_check_result: "unchanged", last_checked_at: 2.hours.ago)
    get scheduled_tasks_path
    expect(response.body).to include("nothing new")
  end
end
