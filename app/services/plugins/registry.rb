# frozen_string_literal: true

module Plugins
  # In-memory store of all loaded plugins and their metadata.
  # Provides lookup, enable/disable, and extension point queries.
  class Registry
    class << self
      # @param name [String] unique plugin identifier from the manifest
      # @param manifest [Plugins::Manifest] parsed manifest for the plugin
      # @param path [String] absolute filesystem path to the plugin directory
      # @return [Hash] the stored plugin entry
      def register_plugin(name:, manifest:, path:)
        plugins[name] = {
          name: name,
          manifest: manifest,
          path: path,
          status: :active,
          loaded_at: Time.current
        }
      end

      # @param name [String] plugin name to remove
      # @return [Hash, nil] the removed plugin entry, or nil if not found
      def unregister_plugin(name)
        plugins.delete(name)
      end

      # @return [Array<Hash>] all plugins with +:active+ status
      def loaded
        plugins.values.select { |p| p[:status] == :active }
      end

      # @param name [String] plugin name
      # @return [Hash, nil] the plugin entry or nil
      def find(name)
        plugins[name]
      end

      # @param type [String] extension type ("channel", "tool", "hook", "memory")
      # @return [Array<Plugins::Manifest::ExtensionPoint>] matching extension points across all active plugins
      def extension_points_for(type)
        loaded.flat_map do |plugin|
          plugin[:manifest].extension_points.select { |ext| ext.type == type }
        end
      end

      # @param name [String] plugin name
      # @return [Boolean]
      def active?(name)
        plugin = plugins[name]
        return false unless plugin

        plugin[:status] == :active
      end

      # @param name [String] plugin name
      # @return [ServiceResponse] success with new status, or failure if not found
      def disable(name)
        plugin = plugins[name]
        return ServiceResponse.failure(error: "Plugin not found: #{name}") unless plugin

        plugin[:status] = :disabled
        ServiceResponse.success(data: { name: name, status: :disabled })
      end

      # @param name [String] plugin name
      # @return [ServiceResponse] success with new status, or failure if not found
      def enable(name)
        plugin = plugins[name]
        return ServiceResponse.failure(error: "Plugin not found: #{name}") unless plugin

        plugin[:status] = :active
        ServiceResponse.success(data: { name: name, status: :active })
      end

      # Clears all registered plugins. Intended for tests.
      # @return [Hash] empty hash
      def reset!
        @plugins = {}
      end

      # @return [Integer] total number of registered plugins (active and disabled)
      def count
        plugins.size
      end

      private

      def plugins
        @plugins ||= {}
      end
    end
  end
end
