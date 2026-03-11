# frozen_string_literal: true

module Plugins
  class Loader
    PLUGIN_DIR = Rails.root.join("plugins")
    MANIFEST_FILENAME = "hivemind-plugin.yml"

    def self.load_all
      return ServiceResponse.success(data: { loaded: [] }) unless PLUGIN_DIR.exist?

      loaded = []
      errors = []

      PLUGIN_DIR.children.select(&:directory?).each do |dir|
        result = load_plugin(dir)
        if result.success?
          loaded << result.data[:plugin_name]
        else
          errors << result.error
        end
      end

      if errors.any?
        Rails.logger.warn("[Plugins] #{errors.size} plugin(s) failed to load: #{errors.join('; ')}")
      end

      ServiceResponse.success(data: { loaded: loaded, errors: errors })
    end

    def self.load_plugin(dir)
      manifest_path = dir.join(MANIFEST_FILENAME)

      unless manifest_path.exist?
        return ServiceResponse.failure(error: "No manifest in #{dir.basename}")
      end

      manifest = Manifest.load(path: manifest_path.to_s)

      # Load Ruby files from lib/
      lib_dir = dir.join("lib")
      if lib_dir.exist?
        Dir[lib_dir.join("**", "*.rb")].sort.each { |f| require f }
      end

      # Register extension points
      manifest.extension_points.each do |ext|
        register_extension_point(ext, plugin_name: manifest.name)
      end

      # Register in the plugin registry
      Registry.register_plugin(
        name: manifest.name,
        manifest: manifest,
        path: dir.to_s
      )

      Rails.logger.info("[Plugins] Loaded plugin: #{manifest.name} v#{manifest.version}")
      ServiceResponse.success(data: { plugin_name: manifest.name })
    rescue ArgumentError => e
      ServiceResponse.failure(error: "Plugin #{dir.basename}: #{e.message}")
    rescue StandardError => e
      ServiceResponse.failure(error: "Plugin #{dir.basename}: #{e.class} - #{e.message}")
    end

    def self.register_extension_point(ext, plugin_name:)
      case ext.type
      when "channel"
        Channels::Registry.register(ext.id, ext.class_name)
      when "tool"
        Tools::Executor.register(ext.id, ext.class_name)
      when "hook"
        Plugins::Hooks.register(ext.id, ext.class_name)
      end
    rescue StandardError => e
      Rails.logger.error("[Plugins] Failed to register #{ext.type}/#{ext.id} from #{plugin_name}: #{e.message}")
      raise
    end

    private_class_method :register_extension_point
  end
end
