# frozen_string_literal: true

namespace :plugins do
  desc "List all loaded plugins"
  task list: :environment do
    plugins = Plugins::Registry.loaded

    if plugins.empty?
      puts "No plugins loaded."
      puts "Place plugins in #{Plugins::Loader::PLUGIN_DIR}"
      next
    end

    puts "Loaded plugins (#{plugins.size}):"
    puts "-" * 60

    plugins.each do |plugin|
      manifest = plugin[:manifest]
      status = plugin[:status] == :active ? "active" : "disabled"
      puts "  #{manifest.name} v#{manifest.version} [#{status}]"
      puts "    #{manifest.description}" if manifest.description.present?
      puts "    Author: #{manifest.author}" if manifest.author.present?
      puts "    Path: #{plugin[:path]}"

      manifest.extension_points.each do |ext|
        puts "    Extension: #{ext.type}/#{ext.id} -> #{ext.class_name}"
      end

      puts ""
    end
  end
end
