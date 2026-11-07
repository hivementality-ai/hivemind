# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ScheduledTasks quiet hours and digest", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:task) { create(:scheduled_task, precheck_url: "https://example.com/feed.xml") }

  before { sign_in owner }

  it "shows the plain-language fields on the edit form" do
    get edit_scheduled_task_path(task)
    expect(response.body).to include("Don't disturb me between", "Bundle into one morning summary at")
  end

  it "saves the window and the digest hour" do
    patch scheduled_task_path(task), params: { scheduled_task: { quiet_start_hour: "22", quiet_end_hour: "7", digest_hour: "8" } }
    task.reload
    expect([ task.quiet_start_hour, task.quiet_end_hour, task.digest_hour ]).to eq([ 22, 7, 8 ])
  end

  it "clears them when left blank" do
    task.update!(quiet_start_hour: 22, quiet_end_hour: 7, digest_hour: 8)
    patch scheduled_task_path(task), params: { scheduled_task: { quiet_start_hour: "", quiet_end_hour: "", digest_hour: "" } }
    task.reload
    expect([ task.quiet_start_hour, task.quiet_end_hour, task.digest_hour ]).to eq([ nil, nil, nil ])
  end

  it "shows what is being held and when it goes out" do
    task.update!(quiet_start_hour: 22, quiet_end_hour: 7)
    task.hold([ { id: "a", title: "A" }, { id: "b", title: "B" }, { id: "c", title: "C" } ], extra: 0)
    task.save!
    get scheduled_tasks_path
    expect(response.body).to include("Holding 3 new items until 7:00")
  end

  it "shows nothing new today for an empty digest" do
    task.update!(digest_hour: 7)
    get scheduled_tasks_path
    expect(response.body).to include("Nothing new today")
  end
end
