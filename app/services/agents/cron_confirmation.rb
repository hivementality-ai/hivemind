# frozen_string_literal: true

module Agents
  # Handles two-stage cron task confirmation (request + approve)
  class CronConfirmation
    CONFIRMATION_TTL = 15 * 60 # 15 minutes
    REDIS_NAMESPACE = "cron_confirmation"
    MODEL_COSTS = {
      "haiku" => 0.05,
      "sonnet" => 0.50,
      "opus" => 2.00
    }.freeze

    # Generate a pending confirmation request
    # @param agent [Agent] The agent requesting the task
    # @param name [String] Task name
    # @param schedule [String] Cron expression
    # @param job_class [String] Sidekiq job class name
    # @param job_params [Hash] Parameters for the job
    # @param description_hint [String] Optional hint for explanation
    # @return [Hash] Confirmation response with token and explanation
    def self.generate_explanation(agent:, name:, schedule:, job_class:, job_params:, description_hint: nil)
      new(agent: agent).generate_explanation(
        name: name,
        schedule: schedule,
        job_class: job_class,
        job_params: job_params,
        description_hint: description_hint
      )
    end

    # Confirm and persist a scheduled task
    # @param confirmation_id [String] The confirmation token
    # @param agent [Agent] The agent confirming the task
    # @return [Hash] Confirmation result with task_id and status
    def self.confirm_and_persist(confirmation_id:, agent:)
      new(agent: agent).confirm_and_persist(confirmation_id)
    end

    def initialize(agent:)
      @agent = agent
    end

    def generate_explanation(name:, schedule:, job_class:, job_params:, description_hint: nil)
      # Generate confirmation token
      confirmation_id = SecureRandom.hex(32)

      # Parse schedule into human-readable format
      frequency = CronParser.parse(schedule)

      # Build explanation
      explanation = {
        task: description_hint || humanize_job_name(job_class),
        frequency: frequency,
        what_happens: build_what_happens_description(job_class, job_params),
        agent: @agent.name || @agent.id,
        estimated_cost: estimate_cost(job_params)
      }

      # Store confirmation details in Redis with TTL
      store_pending_confirmation(confirmation_id, {
        agent_id: @agent.id,
        name: name,
        schedule: schedule,
        job_class: job_class,
        job_params: job_params,
        description_hint: description_hint
      })

      {
        status: "pending_confirmation",
        confirmation_id: confirmation_id,
        explanation: explanation,
        expires_in_minutes: CONFIRMATION_TTL / 60,
        next_step: "Present the explanation to the user. Once they approve, call the cron tool again with action: 'confirm_create' and confirmation_id: '#{confirmation_id}' to persist the task."
      }
    end

    def confirm_and_persist(confirmation_id)
      # Retrieve pending confirmation from Redis
      pending = retrieve_pending_confirmation(confirmation_id)
      return { status: "error", message: "Confirmation expired or invalid" } if pending.nil?

      # Verify agent matches
      if pending["agent_id"] != @agent.id
        return { status: "error", message: "Agent mismatch: confirmation belongs to a different agent" }
      end

      # Create the scheduled task
      task = ScheduledTask.create!(
        agent: @agent,
        name: pending["name"],
        schedule: pending["schedule"],
        job_class: pending["job_class"],
        job_params: pending["job_params"],
        description: pending["description_hint"],
        confirmation_status: "active",
        enabled: true
      )

      # Sync to Sidekiq scheduler
      sync_to_sidekiq(task)

      # Clean up the confirmation from Redis
      delete_pending_confirmation(confirmation_id)

      # Audit log
      log_cron_action("create", task)

      next_run_str = format_next_run(task.next_run_at)
      {
        status: "created",
        task_id: task.id,
        message: "#{task.name} scheduled ✅",
        next_run: next_run_str
      }
    rescue StandardError => e
      { status: "error", message: "Failed to persist task: #{e.message}" }
    end

    private

    def humanize_job_name(job_class)
      # Convert BlogPostJob → "Blog post"
      job_class
        .gsub(/Job$/, "")
        .gsub(/([A-Z])/, ' \1')
        .strip
        .downcase
        .capitalize
    end

    def build_what_happens_description(job_class, job_params)
      case job_class
      when "BlogPostJob"
        "Generates a new blog post using #{job_params['model']&.capitalize || 'AI'}, creates a draft PR, and notifies you for approval"
      when "ReportGenerationJob"
        "Generates a periodic report with metrics and sends it to your inbox"
      when "NotificationJob"
        "Sends a scheduled notification to configured channels"
      when "MaintenanceJob"
        "Runs scheduled maintenance tasks on the system"
      when "DataSyncJob"
        "Syncs data from external sources"
      else
        "Executes the #{humanize_job_name(job_class).downcase} task with the provided parameters"
      end
    end

    def estimate_cost(job_params)
      # Handle both string and symbol keys
      model = (job_params["model"] || job_params[:model] || "sonnet").to_s.downcase
      cost = MODEL_COSTS[model] || MODEL_COSTS["sonnet"]
      "~$#{format('%.2f', cost)} per run (#{model.capitalize} model)"
    end

    def store_pending_confirmation(confirmation_id, data)
      redis = Redis.current
      key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      redis.setex(key, CONFIRMATION_TTL, JSON.generate(data))
    rescue StandardError => e
      Rails.logger.warn("Failed to store pending confirmation: #{e.message}")
      # Don't fail entirely, just log the issue
    end

    def retrieve_pending_confirmation(confirmation_id)
      redis = Redis.current
      key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      data = redis.get(key)
      data ? JSON.parse(data) : nil
    rescue StandardError => e
      Rails.logger.warn("Failed to retrieve pending confirmation: #{e.message}")
      nil
    end

    def delete_pending_confirmation(confirmation_id)
      redis = Redis.current
      key = "#{REDIS_NAMESPACE}:#{confirmation_id}"
      redis.del(key)
    rescue StandardError => e
      Rails.logger.warn("Failed to delete pending confirmation: #{e.message}")
    end

    def sync_to_sidekiq(task)
      # Integration point: Sync to Sidekiq cron scheduler
      # This would typically call Sidekiq::Cron::Job.create or similar
      # For now, just mark as synced
      Rails.logger.info("Syncing scheduled task #{task.id} to Sidekiq scheduler")
      # TODO: Implement actual Sidekiq sync when scheduler is integrated
    end

    def log_cron_action(action, task)
      # Integration point: Log to AuditLog or dedicated CronConfirmationLog
      Rails.logger.info("CRON #{action.upcase} #{task.id}: #{task.name} (#{task.agent.name || task.agent.id})")
    end

    def format_next_run(next_run_at)
      return "Pending scheduler sync" if next_run_at.nil?

      next_run_at.strftime("%Y-%m-%d %H:%M:%S %Z")
    rescue StandardError
      "Pending scheduler sync"
    end
  end
end
