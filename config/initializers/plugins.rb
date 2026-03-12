# frozen_string_literal: true

Rails.application.config.after_initialize do
  if Plugins::Loader::PLUGIN_DIR.exist?
    result = Plugins::Loader.load_all
    if result.success? && result.data[:loaded].any?
      Rails.logger.info("[Plugins] Loaded #{result.data[:loaded].size} plugin(s): #{result.data[:loaded].join(', ')}")
    end
  end
rescue StandardError => e
  Rails.logger.error("[Plugins] Failed to load plugins: #{e.message}")
end
