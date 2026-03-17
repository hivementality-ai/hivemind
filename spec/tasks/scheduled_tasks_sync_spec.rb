# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "scheduled_tasks:sync", type: :task do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:task) { Rake::Task["scheduled_tasks:sync"] }

  before do
    task.reenable
    allow(Sidekiq::Cron::Job).to receive(:create).and_return(true)
  end

  it "syncs active enabled tasks to Sidekiq Cron" do
    scheduled = create(:scheduled_task, enabled: true, confirmation_status: "active", schedule: "0 9 * * *")

    expect { task.invoke }.to output(/Synced: 1/).to_stdout

    expect(Sidekiq::Cron::Job).to have_received(:create).with(
      hash_including(
        name: "scheduled_task_#{scheduled.id}",
        cron: "0 9 * * *",
        class: scheduled.job_class,
        args: [ scheduled.id ]
      )
    )
  end

  it "skips disabled tasks" do
    create(:scheduled_task, :disabled, confirmation_status: "active")

    expect { task.invoke }.to output(/Found 0 active/).to_stdout
    expect(Sidekiq::Cron::Job).not_to have_received(:create)
  end

  it "skips pending confirmation tasks" do
    create(:scheduled_task, :pending_confirmation, enabled: true)

    expect { task.invoke }.to output(/Found 0 active/).to_stdout
    expect(Sidekiq::Cron::Job).not_to have_received(:create)
  end

  it "handles sync failures gracefully" do
    create(:scheduled_task, enabled: true, confirmation_status: "active")
    allow(Sidekiq::Cron::Job).to receive(:create).and_return(false)

    expect { task.invoke }.to output(/Failed: 1/).to_stdout
  end

  it "reports count of synced tasks" do
    create_list(:scheduled_task, 3, enabled: true, confirmation_status: "active")

    expect { task.invoke }.to output(/Synced: 3, Failed: 0/).to_stdout
  end
end
