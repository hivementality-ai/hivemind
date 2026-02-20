# Creating a Tool with Vault Credentials

Step-by-step guide to building a new tool executor that reads API credentials from the vault.

We'll use a fictional "Acme API" as the example, then reference real tools (Trello, Jira) for patterns.

---

## Overview

A tool in Hivemind has 4 parts:

| Part | File | Purpose |
|------|------|---------|
| **Executor** | `app/services/tools/<name>_executor.rb` | Ruby class that handles the logic |
| **Registration** | `app/services/tools/executor.rb` | Maps executor_type → class |
| **Validation** | `app/models/tool.rb` | Allows the executor_type string |
| **Seed** | `db/seeds/tools.rb` | Creates the Tool record in the DB |

Optional but recommended:
- **Integration UI** — form on `/integrations` to save credentials
- **Skill** — instructions for agents on how/when to use the tool

---

## Step 1: Store Credentials in the Vault

Credentials are stored as `VaultEntry` records with a **namespace** and **key**.

Convention: use the tool name as namespace.

```ruby
# Examples:
VaultEntry: namespace="trello", key="api_key"
VaultEntry: namespace="trello", key="token"
VaultEntry: namespace="jira",   key="base_url"
VaultEntry: namespace="jira",   key="email"
VaultEntry: namespace="jira",   key="api_token"
```

Credentials can be stored via:
- The **Integrations UI** (`/integrations`) — add a form in `IntegrationsController`
- **Rails console** — `VaultEntry.create!(namespace: "acme", key: "api_key", value: "secret")`
- The **vault tool** — agents can request writes (requires confirmation)

> ⚠️ **Vault values are always redacted when returned to agents.** Agents see `sk-...ab1c`, never the full value. This is why tools must read vault server-side.

---

## Step 2: Create the Executor

Create `app/services/tools/acme_executor.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Tools
  class AcmeExecutor < BaseExecutor
    # Acme API integration.
    #
    # Credentials stored in vault:
    #   acme/api_key   — API key from https://acme.com/settings
    #   acme/base_url  — API base URL (optional, defaults to https://api.acme.com)

    def call
      action = input["action"].to_s.strip

      case action
      when "list_items"  then list_items
      when "get_item"    then get_item
      when "create_item" then create_item
      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. Supported: list_items, get_item, create_item"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Acme error: #{e.message}")
    end

    private

    # ─── Actions ───────────────────────────────────────────────────

    def list_items
      response = api_get("/items")
      items = response["items"].map { |i| "#{i['name']} (#{i['id']})" }
      ServiceResponse.success(data: { output: "Items:\n#{items.join("\n")}" })
    end

    def get_item
      id = input["item_id"].to_s.strip
      raise "item_id is required" if id.empty?

      response = api_get("/items/#{id}")
      ServiceResponse.success(data: { output: JSON.pretty_generate(response) })
    end

    def create_item
      name = input["name"].to_s.strip
      raise "name is required" if name.empty?

      response = api_post("/items", { name: name, description: input["description"] })
      ServiceResponse.success(data: { output: "Created: #{response['name']} (#{response['id']})" })
    end

    # ─── HTTP ──────────────────────────────────────────────────────

    def api_get(path)
      request(:get, path)
    end

    def api_post(path, body)
      request(:post, path, body)
    end

    def request(method, path, body = nil)
      uri = URI("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      req = case method
      when :get  then Net::HTTP::Get.new(uri)
      when :post then Net::HTTP::Post.new(uri)
      when :put  then Net::HTTP::Put.new(uri)
      end

      # ─── Auth: inject credentials server-side ───
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"

      req.body = body.to_json if body

      response = http.request(req)

      unless response.is_a?(Net::HTTPSuccess)
        error_body = begin
          JSON.parse(response.body)
        rescue StandardError
          response.body
        end
        raise "HTTP #{response.code}: #{error_body}"
      end

      return {} if response.body.blank?
      JSON.parse(response.body)
    end

    # ─── Credentials ───────────────────────────────────────────────
    # Read from vault, fall back to ENV vars.

    def api_key
      @api_key ||= vault_get("acme", "api_key") || ENV["ACME_API_KEY"] ||
        raise("Acme API key not configured. Add it at /integrations")
    end

    def base_url
      @base_url ||= (vault_get("acme", "base_url") || ENV["ACME_BASE_URL"] || "https://api.acme.com").chomp("/")
    end

    def vault_get(namespace, key)
      VaultEntry.find_by(namespace: namespace, key: key)&.value
    end
  end
end
```

### Key patterns:
- **Extend `BaseExecutor`** — gives you `input`, `config`, `agent` accessors
- **Return `ServiceResponse.success` or `.failure`** — the tool framework expects this
- **Read vault with `VaultEntry.find_by`** — never expose raw values to the agent
- **Fall back to ENV vars** — useful for Docker/development setups
- **Raise helpful errors** — tell agents where to configure missing credentials

---

## Step 3: Register the Executor

In `app/services/tools/executor.rb`, add to the `EXECUTORS` hash:

```ruby
EXECUTORS = {
  # ... existing tools ...
  "acme" => Tools::AcmeExecutor,
}.freeze
```

---

## Step 4: Add to Validation

In `app/models/tool.rb`, add `"acme"` to the `executor_type` inclusion list:

```ruby
validates :executor_type, presence: true, inclusion: {
  in: %w[shell file_read ... jira acme ...]
}
```

---

## Step 5: Add the Seed

In `db/seeds/tools.rb`, add the tool definition:

```ruby
{
  name: "acme",
  description: "Manage Acme items. List, get, and create items.",
  executor_type: "acme",
  requires_approval: false,
  parameters_schema: {
    "properties" => {
      "action" => {
        "type" => "string",
        "description" => "Action to perform",
        "enum" => %w[list_items get_item create_item]
      },
      "item_id" => {
        "type" => "string",
        "description" => "Item ID (for get_item)"
      },
      "name" => {
        "type" => "string",
        "description" => "Item name (for create_item)"
      },
      "description" => {
        "type" => "string",
        "description" => "Item description (for create_item)"
      }
    },
    "required" => ["action"]
  }
}
```

The `parameters_schema` is critical — it's what the LLM sees to know what parameters to pass.

---

## Step 6: Add Integration UI (Optional)

In `IntegrationsController`, add save and test actions:

```ruby
def update_acme
  api_key = params[:acme_api_key].to_s.strip

  if api_key.present?
    store_vault("acme", "api_key", api_key)
    redirect_to integrations_path, notice: "Acme connected"
  else
    redirect_to integrations_path, alert: "API key required"
  end
end

def test_acme
  api_key = VaultEntry.find_by(namespace: "acme", key: "api_key")&.value
  return render(json: { status: "error", message: "Acme not configured" }, status: :unprocessable_entity) unless api_key

  # Make a test API call
  uri = URI("https://api.acme.com/me")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{api_key}"
  # ... handle response ...
end
```

Add routes:
```ruby
patch "integrations/acme", to: "integrations#update_acme"
get "integrations/acme/test", to: "integrations#test_acme"
```

---

## Step 7: Deploy

```bash
# Rebuild containers (picks up new Ruby code)
docker compose build app worker

# Restart
docker compose up -d

# Seed the new tool into the database
docker compose exec app bash -c 'bundle exec rails db:seed'

# Assign tool to agents (via UI or console)
docker compose exec app bash -c 'bundle exec rails console'
> agent = Agent.find_by(name: "Bobby")
> agent.tools << Tool.find_by(name: "acme")
```

---

## Auth Patterns

Different APIs use different auth. Here are patterns from existing tools:

### Bearer Token (most common)
```ruby
req["Authorization"] = "Bearer #{api_key}"
```

### Basic Auth (Jira)
```ruby
req["Authorization"] = "Basic #{Base64.strict_encode64("#{email}:#{token}")}"
```

### Query Parameter Auth (Trello)
```ruby
def api_get(path, **params)
  params[:key] = api_key
  params[:token] = api_token
  query = URI.encode_www_form(params)
  request(:get, "#{path}?#{query}")
end
```

### API Key Header
```ruby
req["X-API-Key"] = api_key
```

---

## Real Examples

| Tool | Auth Pattern | Vault Keys | Reference |
|------|-------------|------------|-----------|
| Jira | Basic (email:token) | `jira/base_url`, `jira/email`, `jira/api_token` | `jira_executor.rb` |
| Trello | Query params (key+token) | `trello/api_key`, `trello/token` | `trello_executor.rb` |
| Gmail | IMAP/SMTP credentials | `google/gmail_address`, `google/gmail_app_password` | `gmail_executor.rb` |
| Image Generate | Bearer token | `openai/api_key` | `image_generate_executor.rb` |

---

## Checklist

- [ ] Executor class created (`app/services/tools/<name>_executor.rb`)
- [ ] Registered in `EXECUTORS` hash (`app/services/tools/executor.rb`)
- [ ] Added to `executor_type` validation (`app/models/tool.rb`)
- [ ] Seed definition added (`db/seeds/tools.rb`)
- [ ] Integration UI form (optional, `IntegrationsController`)
- [ ] Routes added (optional)
- [ ] Containers rebuilt (`docker compose build app worker`)
- [ ] Tool seeded (`rails db:seed`)
- [ ] Tool assigned to agents
- [ ] Skill created with usage instructions (optional)
