# frozen_string_literal: true

module Library
  # Settings and status for the watched library folder: the on/off switch,
  # where the folder is mounted, and the result of the last scan.
  module FolderSetting
    ENABLED_KEY   = "library_folder_enabled"
    LAST_SCAN_KEY = "library_folder_last_scan"
    AGENT_KEY     = "library_folder_agent_id"

    module_function

    # @return [Pathname] where the host folder is mounted inside the container
    def root
      Pathname.new(ENV.fetch("HIVEMIND_LIBRARY_ROOT", "/library"))
    end

    # On by default whenever the folder is mounted; an explicit choice wins.
    def enabled?(root: self.root)
      case Setting.get(ENABLED_KEY)
      when "true" then true
      when "false" then false
      else root.directory?
      end
    end

    def enabled=(value)
      Setting.set(ENABLED_KEY, value ? "true" : "false")
    end

    # @return [String] the folder's name on the host, in plain words
    def folder_name
      host = ENV.fetch("HIVEMIND_LIBRARY_HOST_DIR", "").to_s
      File.basename(host.presence || "Hivemind Library")
    end

    # @return [Hash, nil] counts and time from the most recent scan
    def last_scan
      raw = Setting.get(LAST_SCAN_KEY)
      raw.present? ? JSON.parse(raw) : nil
    rescue JSON::ParserError
      nil
    end

    def record_scan(result)
      Setting.set(LAST_SCAN_KEY, result.to_h.merge(at: Time.current.iso8601).to_json)
    end

    # The agent that owns watched documents: an explicit choice, else the
    # top-level enabled agent, else any enabled agent.
    def agent
      chosen = Setting.get(AGENT_KEY).presence
      return Agent.enabled.find_by(id: chosen) if chosen && Agent.enabled.exists?(id: chosen)

      visible = Agent.enabled.visible.order(:id)
      visible.find_by(reports_to_id: nil) || visible.first
    end
  end
end
