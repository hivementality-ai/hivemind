# frozen_string_literal: true

module Hivemind
  class Doctor
    CHECK_METHODS = %i[
      check_postgresql
      check_redis
      check_sidekiq
      check_workspace
      check_heartbeat
      check_channels
      check_agents
      check_providers
      check_vault
      check_skills
      check_docker
      check_disk_space
      check_delivery_queue
    ].freeze

    def self.run_all
      CHECK_METHODS.flat_map { |method| send(method) }
    end

    def self.run_all_as_hash
      checks = run_all
      {
        timestamp: Time.current.iso8601,
        healthy: checks.none? { |c| c[:status] == :error },
        checks: checks
      }
    end

    def self.print_results(checks)
      puts ""
      puts "Hivemind Doctor"
      puts "=" * 50
      puts ""

      checks.each do |check|
        icon = case check[:status]
        when :ok then "\u2705"
        when :warning then "\u26A0\uFE0F "
        when :error then "\u274C"
        end

        line = "#{icon} #{check[:name]}"
        line += ": #{check[:detail]}" if check[:detail]
        puts line
      end

      ok_count = checks.count { |c| c[:status] == :ok }
      warn_count = checks.count { |c| c[:status] == :warning }
      error_count = checks.count { |c| c[:status] == :error }

      puts ""
      puts "#{ok_count} passed, #{warn_count} warnings, #{error_count} errors"
      puts ""
    end

    def self.check_postgresql
      connected = ActiveRecord::Base.connection.active? rescue false
      if connected
        version = ActiveRecord::Base.connection.select_value("SELECT version()").to_s.split(" ")[1]
        [ { name: "PostgreSQL", status: :ok, detail: "Connected (v#{version})" } ]
      else
        [ { name: "PostgreSQL", status: :error, detail: "Cannot connect" } ]
      end
    end

    def self.check_redis
      redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
      pong = redis.ping == "PONG"
      if pong
        info = redis.info("memory")
        used = (info["used_memory_human"] rescue "unknown")
        [ { name: "Redis", status: :ok, detail: "Connected (#{used} used)" } ]
      else
        [ { name: "Redis", status: :error, detail: "Ping failed" } ]
      end
    rescue StandardError => e
      [ { name: "Redis", status: :error, detail: e.message } ]
    end

    def self.check_sidekiq
      processes = Sidekiq::ProcessSet.new.size
      failed = Sidekiq::Stats.new.failed.to_i
      if processes > 0
        [ { name: "Sidekiq", status: :ok, detail: "#{processes} processes, #{failed} failed jobs" } ]
      else
        [ { name: "Sidekiq", status: :error, detail: "No processes running" } ]
      end
    rescue StandardError => e
      [ { name: "Sidekiq", status: :error, detail: e.message } ]
    end

    def self.check_workspace
      running = File.directory?("/workspace") rescue false
      if running
        [ { name: "Workspace container", status: :ok, detail: "Running" } ]
      else
        [ { name: "Workspace container", status: :warning, detail: "Not detected (optional)" } ]
      end
    end

    def self.check_heartbeat
      raw = Setting.get("heartbeat") rescue nil
      config = raw ? (JSON.parse(raw) rescue {}) : {}
      if config["enabled"]
        last_run = Setting.get("heartbeat_last_run") rescue nil
        detail = last_run ? "Enabled (last run: #{last_run})" : "Enabled (never run)"
        [ { name: "Heartbeat", status: :ok, detail: detail } ]
      else
        [ { name: "Heartbeat", status: :warning, detail: "Disabled (consider enabling)" } ]
      end
    end

    def self.check_channels
      total = Channel.count
      enabled = Channel.enabled_channels.count
      if total == 0
        [ { name: "Channels", status: :warning, detail: "No channels configured" } ]
      else
        [ { name: "Channels", status: :ok, detail: "#{enabled}/#{total} enabled" } ]
      end
    end

    def self.check_agents
      total = Agent.count
      enabled = Agent.where(enabled: true).count
      if total == 0
        [ { name: "Agents", status: :warning, detail: "No agents configured" } ]
      else
        results = [ { name: "Agents", status: :ok, detail: "#{enabled} enabled (#{total} total)" } ]
        Agent.where(enabled: true).find_each do |agent|
          next if agent.system_agent?
          if agent.tools.count == 0
            results << { name: "Agent \"#{agent.name}\"", status: :warning, detail: "No tools assigned" }
          end
        end
        results
      end
    end

    def self.check_providers
      configs = ProviderConfig.all
      return [ { name: "Providers", status: :warning, detail: "No providers configured" } ] if configs.empty?
      configs.map do |config|
        if config.enabled?
          has_key = config.api_key.present? || config.adapter_type == "ollama"
          if has_key
            { name: "Provider: #{config.adapter_type}", status: :ok, detail: "Configured" }
          else
            { name: "Provider: #{config.adapter_type}", status: :error, detail: "API key missing" }
          end
        else
          { name: "Provider: #{config.adapter_type}", status: :warning, detail: "Disabled" }
        end
      end
    end

    def self.check_vault
      count = VaultEntry.count
      [ { name: "Vault", status: :ok, detail: "#{count} entries" } ]
    rescue StandardError => e
      [ { name: "Vault", status: :error, detail: e.message } ]
    end

    def self.check_skills
      total = Skill.count
      return [ { name: "Skills", status: :ok, detail: "None configured" } ] if total == 0
      enabled = Skill.where(enabled: true).count
      [ { name: "Skills", status: :ok, detail: "#{enabled}/#{total} enabled" } ]
    end

    def self.check_docker
      version = `docker --version 2>/dev/null`.strip
      if version.present?
        ver = version.match(/(\d+\.\d+\.\d+)/)&.captures&.first || version
        [ { name: "Docker", status: :ok, detail: "Version #{ver}" } ]
      else
        [ { name: "Docker", status: :warning, detail: "Not found in PATH" } ]
      end
    rescue StandardError
      [ { name: "Docker", status: :warning, detail: "Not available" } ]
    end

    def self.check_disk_space
      output = `df -h / 2>/dev/null`.strip
      lines = output.split("\n")
      if lines.size >= 2
        parts = lines[1].split
        usage_percent = parts[4]&.to_i || 0
        available = parts[3]
        status = if usage_percent > 90
          :error
        elsif usage_percent > 75
          :warning
        else
          :ok
        end
        [ { name: "Disk space", status: status, detail: "#{usage_percent}% used (#{available} free)" } ]
      else
        [ { name: "Disk space", status: :warning, detail: "Could not determine" } ]
      end
    rescue StandardError
      [ { name: "Disk space", status: :warning, detail: "Could not check" } ]
    end

    def self.check_delivery_queue
      pending = DeliveryQueueEntry.pending.count
      dead = DeliveryQueueEntry.dead_letter.count
      if dead > 0
        [ { name: "Delivery queue", status: :warning, detail: "#{pending} pending, #{dead} dead letter" } ]
      else
        [ { name: "Delivery queue", status: :ok, detail: "#{pending} pending" } ]
      end
    rescue StandardError => e
      [ { name: "Delivery queue", status: :error, detail: e.message } ]
    end
  end
end
