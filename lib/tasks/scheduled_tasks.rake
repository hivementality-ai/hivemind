# frozen_string_literal: true

namespace :scheduled_tasks do
  desc "Sync all active scheduled tasks to Sidekiq Cron (backfill for tasks created before sync was implemented)"
  task sync: :environment do
    tasks = ScheduledTask.where(enabled: true, confirmation_status: "active")
    puts "Found #{tasks.count} active scheduled tasks to sync..."

    synced = 0
    failed = 0

    tasks.find_each do |task|
      cron_name = "scheduled_task_#{task.id}"
      result = Sidekiq::Cron::Job.create(
        name: cron_name,
        cron: task.schedule,
        class: task.job_class,
        args: [ task.id ]
      )

      if result
        synced += 1
        puts "  ✓ [#{task.id}] #{task.name} — #{task.schedule}"
      else
        failed += 1
        puts "  ✗ [#{task.id}] #{task.name} — failed to sync"
      end
    rescue StandardError => e
      failed += 1
      puts "  ✗ [#{task.id}] #{task.name} — #{e.message}"
    end

    puts "\nDone. Synced: #{synced}, Failed: #{failed}"
  end
end
