# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates ScheduledTask records from a SwarmDocument's scheduled_tasks[] section.
    #
    # Each entry must have:
    #   name     – task name (used to find existing records for resolution)
    #   schedule – cron expression
    #   agent    – agent name the task should belong to
    #
    # Optional fields:
    #   description – human-readable description
    #   enabled     – boolean (defaults to true when absent)
    #   params      – Hash of additional parameters
    #
    # Resolution strategies are keyed by task name:
    #   :skip      – keep existing task unchanged
    #   :overwrite – update existing task with swarm values
    #   :rename    – create new task with an auto-suffixed name
    #   (none)     – create new task (no conflict)
    #
    # Agent lookup: tasks are scoped by agent. If the named agent does not exist
    # the entry is skipped and a warning is added to the result.
    # Conflict detection is scoped to the owning agent so same-named tasks
    # belonging to different agents are not treated as conflicts.
    #
    # Usage:
    #   result = ScheduledTasksDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?                     # => true / false
    #   result.payload[:scheduled_tasks]    # => [DeployResult, ...]
    class ScheduledTasksDeployer
      DeployResult = Data.define(:name, :record, :action) do
        # action – :created | :updated | :skipped | :renamed | :agent_missing
      end

      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = Array(@document.scheduled_tasks).map do |entry|
          deploy_task(entry.with_indifferent_access)
        end

        ServiceResponse.success(payload: { scheduled_tasks: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy scheduled tasks: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy scheduled tasks: #{e.message}")
      end

      private

      def deploy_task(entry)
        name       = entry[:name].to_s
        agent_name = entry[:agent].to_s
        strategy   = @resolutions[name]&.to_sym

        agent = Agent.find_by(name: agent_name)
        unless agent
          Rails.logger.warn("[ScheduledTasksDeployer] Agent '#{agent_name}' not found — skipping task '#{name}'")
          return DeployResult.new(name: name, record: nil, action: :agent_missing)
        end

        # Scope the conflict check to this agent — same-named tasks on different
        # agents are independent and must not be treated as conflicts.
        existing = agent.scheduled_tasks.find_by(name: name)

        if existing.nil?
          record = create_task(name, entry, agent)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, entry, agent)
        end
      end

      def create_task(name, entry, agent)
        ScheduledTask.create!(build_attributes(name, entry, agent))
      end

      def apply_strategy(strategy, existing, name, entry, agent)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, entry, agent))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name, agent)
          record   = create_task(new_name, entry.merge(name: new_name), agent)
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # Conflict with no resolution provided — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, entry, agent)
        attrs = {
          name:     name,
          schedule: entry[:schedule].to_s,
          agent:    agent,
          enabled:  entry.key?(:enabled) ? entry[:enabled] : true
        }

        attrs[:description] = entry[:description].presence if entry[:description].present?
        attrs[:params]      = entry[:params]               if entry[:params].is_a?(Hash)

        attrs
      end

      # Finds a unique name for the task scoped to the owning agent.
      def unique_name(base, agent)
        candidate = "#{base}-2"
        counter   = 2

        while agent.scheduled_tasks.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
