# frozen_string_literal: true

module Plugins
  class Registry
    class << self
      def register_plugin(name:, manifest:, path:)
        plugins[name] = {
          name: name,
          manifest: manifest,
          path: path,
          status: :active,
          loaded_at: Time.current
        }
      end

      def unregister_plugin(name)
        plugins.delete(name)
      end

      def loaded
        plugins.values.select { |p| p[:status] == :active }
      end

      def find(name)
        plugins[name]
      end

      def extension_points_for(type)
        loaded.flat_map do |plugin|
          plugin[:manifest].extension_points.select { |ext| ext.type == type }
        end
      end

      def active?(name)
        plugin = plugins[name]
        return false unless plugin

        plugin[:status] == :active
      end

      def disable(name)
        plugin = plugins[name]
        return ServiceResponse.failure(error: "Plugin not found: #{name}") unless plugin

        plugin[:status] = :disabled
        ServiceResponse.success(data: { name: name, status: :disabled })
      end

      def enable(name)
        plugin = plugins[name]
        return ServiceResponse.failure(error: "Plugin not found: #{name}") unless plugin

        plugin[:status] = :active
        ServiceResponse.success(data: { name: name, status: :active })
      end

      def reset!
        @plugins = {}
      end

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
