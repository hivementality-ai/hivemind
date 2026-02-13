# Hivemind Plugin System

## Overview

Plugins extend Hivemind with new tools, skills, integrations, and channels. They are self-contained directories with a `PLUGIN.md` manifest and optional code files.

## Plugin Types

| Type | Description |
|------|-------------|
| **tool** | Adds a new tool executor agents can use |
| **skill** | Adds reusable skill instructions |
| **integration** | Adds a third-party service integration |
| **channel** | Adds a new communication channel |

## Directory Structure

```
my-plugin/
├── PLUGIN.md      # Required: manifest + documentation
├── executor.rb    # Optional: tool executor class (for type: tool)
├── skill.md       # Optional: skill content (for type: skill)
└── config.yml     # Optional: default configuration
```

## PLUGIN.md Format

The manifest uses YAML frontmatter followed by markdown documentation:

```yaml
---
name: weather-lookup
description: Look up current weather for any location
version: 1.0.0
author: Your Name
homepage: https://github.com/you/weather-lookup
type: tool
requires:
  tools: [http_request]
  config:
    - key: api_key
      label: API Key
      type: secret
      required: true
    - key: units
      label: Units (metric/imperial)
      type: string
      required: false
---

# Weather Lookup Plugin

This plugin provides weather lookup capabilities to your agents.

## Usage

Once enabled, agents with the weather-lookup tool can check weather
for any location worldwide.
```

## Plugin Discovery

Plugins are discovered from these locations (highest precedence first):

1. `/workspace/plugins/` — User-installed plugins
2. `<app>/plugins/` — Built-in plugins shipped with Hivemind

Run discovery from the UI (Plugins > Discover) or programmatically:

```ruby
Plugins::Registry.discover!
```

## Installation

### Via UI Upload

1. Navigate to Plugins > Install Plugin
2. Upload a `PLUGIN.md` file
3. Configure any required settings on the plugin's show page
4. Enable the plugin

### Via File System

1. Create a directory in `/workspace/plugins/your-plugin-name/`
2. Add a `PLUGIN.md` with the manifest
3. Add any additional files (executor.rb, etc.)
4. Run discovery from the Plugins page

## Configuration

Plugins declare their configuration schema in the `requires.config` section of `PLUGIN.md`. Each config field has:

- **key** — The config key stored in the database
- **label** — Human-readable label for the UI
- **type** — `string` or `secret` (secrets are masked in the UI)
- **required** — Whether the field is required

Configuration is stored in the plugin's `config` JSONB column.

## Building a Tool Plugin

### Example: Simple Weather Tool

1. Create `plugins/weather-lookup/PLUGIN.md` (see format above)

2. Create `plugins/weather-lookup/executor.rb`:

```ruby
module Tools
  class WeatherLookupExecutor < BaseExecutor
    def execute(location:, units: "metric", **)
      api_key = plugin_config("api_key")
      return error_response("API key not configured") unless api_key

      # Make HTTP request to weather API
      response = HTTP.get("https://api.weatherapi.com/v1/current.json", params: {
        key: api_key, q: location, units: units
      })

      success_response(response.parse)
    end

    private

    def plugin_config(key)
      Plugin.find_by(name: "weather-lookup")&.config&.dig(key)
    end
  end
end
```

3. Run discovery, configure the API key, and enable the plugin.

When a tool-type plugin is enabled, Hivemind automatically:
- Loads the executor class
- Creates a Tool record (builtin: false)
- Makes it available to agents

When disabled, the tool is disabled but not deleted.

## Migration from OpenClaw Plugins

If you have OpenClaw-compatible plugins, convert them:

1. Rename `SKILL.md` frontmatter fields to match `PLUGIN.md` format
2. Add `type:` field to specify plugin type
3. Move configuration to `requires.config` section
4. Place in `/workspace/plugins/` directory
5. Run discovery
