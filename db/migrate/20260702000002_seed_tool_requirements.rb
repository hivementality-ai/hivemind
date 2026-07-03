# frozen_string_literal: true

class SeedToolRequirements < ActiveRecord::Migration[8.0]
  REQUIREMENTS = {
    "image_generate" => { "provider" => "openai", "description" => "image generation (DALL-E)", "config_hint" => "OpenAI API key must be configured in provider settings" },
    "gmail"          => { "provider" => "google", "description" => "Gmail access", "config_hint" => "Google OAuth credentials must be configured" },
    "drive"          => { "provider" => "google", "description" => "Google Drive access", "config_hint" => "Google OAuth credentials must be configured" },
    "jira"           => { "provider" => "jira", "description" => "Jira integration", "config_hint" => "Jira API token and instance URL must be configured" },
    "tts"            => { "description" => "text-to-speech", "config_hint" => "A TTS provider (ElevenLabs or OpenAI) must be configured" },
    "web_search"     => { "description" => "web search", "config_hint" => "A search provider API key must be configured" },
    "browser"        => { "description" => "browser automation", "config_hint" => "Browser container must be running" }
  }.freeze

  def up
    REQUIREMENTS.each do |name, req|
      execute <<~SQL
        UPDATE tools SET requirements = '#{req.to_json}' WHERE name = '#{name}';
      SQL
    end
  end

  def down
    execute "UPDATE tools SET requirements = '{}' WHERE name IN (#{REQUIREMENTS.keys.map { |n| "'#{n}'" }.join(', ')});"
  end
end
