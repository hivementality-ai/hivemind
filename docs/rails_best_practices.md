# Rails Best Practices

> Steering document for writing clean, scalable, maintainable Rails code.

---

## 1. Core Philosophy

- **Skinny Controllers, Fat Models** — but avoid obese models.  
- **Single Responsibility Principle (SRP):** each class or module should do one thing well.  
- **Explicit over implicit:** always favor readability and clarity.

---

## 2. Controllers

Controllers should handle **HTTP orchestration only**:
- Parsing params
- Authorizing access
- Calling services/queries
- Rendering results or errors

Example:

```ruby
class OrdersController < ApplicationController
  def create
    response = Orders::Create.call(order_params:, user: current_user)

    if response.success?
      render json: response.data[:order], status: :created
    else
      render json: { errors: response.error }, status: :unprocessable_entity
    end
  end

  private

  def order_params
    params.require(:order).permit(:product_id, :quantity)
  end
end
```

---

## 3. Service Objects

### Philosophy

Service objects encapsulate a **single unit of business logic**.  
They should use **keyword arguments only**, and return a standardized **`ServiceResponse`**.

---

### The `ServiceResponse` Class

```ruby
# app/lib/service_response.rb
class ServiceResponse
  attr_reader :success, :data, :error
  alias_method :success?, :success

  def initialize(success:, data: nil, error: nil)
    @success = success
    @data = data
    @error = error
  end

  def self.success(data: nil)
    new(success: true, data:)
  end

  def self.failure(error:)
    new(success: false, error:)
  end
end
```

---

### Example: Orders::Create Service

```ruby
# app/services/orders/create.rb
module Orders
  class Create
    def self.call(order_params:, user:)
      new(order_params:, user:).call
    end

    def initialize(order_params:, user:)
      @order_params = order_params
      @user = user
    end

    def call
      order = Order.new(@order_params.merge(user: @user))

      if order.save
        ServiceResponse.success(data: { order: })
      else
        ServiceResponse.failure(error: order.errors.full_messages)
      end
    end
  end
end
```

---

### Rules

- ✅ Keyword args only (`def call(order_params:, user:)`).
- ✅ Always return a `ServiceResponse`.
- ✅ Stateless and idempotent — no persistent side effects.
- ❌ No positional args.
- ❌ No direct rendering or persistence in controller logic.

---

## 4. Query Objects

Extract reusable data retrieval patterns.

```ruby
# app/queries/orders/recent_for_user.rb
module Orders
  class RecentForUser
    def self.call(user:)
      Order.where(user:).where("created_at > ?", 30.days.ago)
    end
  end
end
```

Use queries for:
- Complex or reusable ActiveRecord scopes.
- Filtering or sorting logic.

---

## 5. Models

Models define:
- Associations
- Validations
- Simple domain logic

Avoid stuffing models with orchestration or data-fetching logic.

Example:

```ruby
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items

  validates :total, numericality: { greater_than: 0 }

  scope :recent, -> { where("created_at > ?", 30.days.ago) }
end
```

---

## 6. Concerns and Modules

- ✅ Use concerns for **shared domain behavior** (e.g. `Searchable`, `Archivable`).
- ❌ Don’t hide complexity by dumping large chunks of logic in them.
- Each concern should define a clear, single responsibility.

---

## 7. Error Handling

Centralize exception handling at the application layer.

```ruby
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not Found" }, status: :not_found
  end
end
```

Services should return `ServiceResponse.failure` with descriptive messages.

---

## 8. Testing Rails Architecture

- **Controllers:** routing, params, and response codes.  
- **Models:** validations and domain behavior.  
- **Services:** input/output contract.  
- **Queries:** correct dataset returned.

Don’t test internal implementation of Rails itself.

---

## 9. Code Organization

- Keep `app/services`, `app/queries`, and `app/lib` structured by domain.  
- Use consistent naming (`Users::Create`, `Payments::Refund`, etc.).  
- Always prefer **explicit dependency injection** (via keyword args) to globals.

---

## 10. Golden Rules

✅ Keyword args only in Service/Query objects.
✅ Always return a `ServiceResponse`.
✅ Controllers orchestrate, don't compute.
✅ Models validate, not coordinate.
✅ Consistency > Cleverness.

---

## 11. Background Jobs

Jobs live in `app/jobs/` and inherit from `ApplicationJob`.

### Queue Priority

Use `:default` for user-facing work and `:low` for background processing:

```ruby
class ChatStreamJob < ApplicationJob
  queue_as :default
end

class MemoryEmbeddingJob < ApplicationJob
  queue_as :low
end
```

### Retry Strategy

Use `retry_on` with polynomial backoff for transient failures:

```ruby
retry_on StandardError, wait: :polynomially_longer, attempts: 3
```

### Guard Clauses for Deleted Records

Jobs run asynchronously — the record may be gone by the time the job executes. Use `find_by` + early return, and rescue `RecordNotFound` as a safety net:

```ruby
def perform(memory_entry_id)
  entry = MemoryEntry.find_by(id: memory_entry_id)
  return unless entry
  return if entry.embedded?

  # ... do work ...
rescue ActiveRecord::RecordNotFound
  # Entry was deleted before job ran — no-op
end
```

### Broadcasting from Jobs

Jobs push real-time updates to the UI via ActionCable:

```ruby
channel = "session_#{session.id}"
ActionCable.server.broadcast(channel, { type: "token", content: chunk })
ActionCable.server.broadcast(channel, { type: "done", content: full_content })
```

### Recursion Guards

When jobs can trigger other jobs (e.g. sub-agent callbacks), cap the depth:

```ruby
class SubAgentJob < ApplicationJob
  MAX_CALLBACK_DEPTH = 3

  def callback_to_parent(sat, reply, success:)
    depth = callback_depth(sat)
    if depth >= MAX_CALLBACK_DEPTH
      broadcast_completion_only(sat, reply, success:)
      return
    end
    # ... fire ChatStreamJob on parent session ...
  end
end
```

---

## 12. Adapter / Registry Pattern

### Base Class with Interface Contract

Define a base class whose methods raise `NotImplementedError`. This enforces a consistent interface across all implementations:

```ruby
# app/services/providers/base.rb
module Providers
  class Base
    def initialize(config:, api_key: nil)
      @config = config
      @api_key = api_key
    end

    def chat(messages:, tools: [], options: {}, &block)
      raise NotImplementedError, "#{self.class}#chat must be implemented"
    end

    def models
      raise NotImplementedError, "#{self.class}#models must be implemented"
    end

    def embed(text:, model: nil)
      raise NotImplementedError, "#{self.class}#embed must be implemented"
    end
  end
end
```

### Registry Hash

Map provider names to concrete adapter classes. Look up by key, instantiate, and return inside a `ServiceResponse`:

```ruby
# app/services/providers/resolver.rb
module Providers
  class Resolver
    ADAPTERS = {
      "openai"    => Providers::OpenaiAdapter,
      "anthropic" => Providers::AnthropicAdapter,
      "ollama"    => Providers::OllamaAdapter
    }.freeze

    def call
      config = ProviderConfig.enabled_providers.find_by(adapter_type: @provider_name)
      adapter_class = ADAPTERS[config.adapter_type]
      adapter = adapter_class.new(config:, api_key: config.api_key(agent: @agent))
      ServiceResponse.success(data: { adapter: })
    end
  end
end
```

### Same Pattern for Channels

The channel adapter layer follows the same shape — base class with `NotImplementedError`, concrete adapters per platform:

```ruby
# app/services/channels/base_adapter.rb
module Channels
  class BaseAdapter
    def receive(message)
      raise NotImplementedError, "#{self.class} must implement #receive"
    end

    def send_message(to:, content:, **options)
      raise NotImplementedError, "#{self.class} must implement #send_message"
    end

    def verify_webhook(request)
      raise NotImplementedError, "#{self.class} must implement #verify_webhook"
    end
  end
end
```

### Rules

- ✅ Every adapter returns a `ServiceResponse`.
- ✅ Base class documents the expected method signatures.
- ✅ Registry is a frozen hash — add new adapters by adding a key.
- ❌ Don't scatter provider conditionals across the codebase — resolve once, use the adapter.

---

## 13. Redis-Backed State

Use Redis for lightweight, cross-process signaling. The canonical example is `SessionSignal`:

```ruby
# app/services/session_signal.rb
class SessionSignal
  NAMESPACE = "session_signal"
  TTL = 60

  TYPES = %w[cancel redirect inject].freeze

  def self.set(session_id, type:, message: nil)
    data = { type: type.to_s, message: message, timestamp: Time.current.iso8601 }.to_json
    Redis.current.setex("#{NAMESPACE}:#{session_id}", TTL, data)
  end

  # Atomic consume — read and delete in one call
  def self.check(session_id)
    data = Redis.current.getdel("#{NAMESPACE}:#{session_id}")
    return nil unless data
    JSON.parse(data, symbolize_names: true)
  end

  def self.clear(session_id)
    Redis.current.del("#{NAMESPACE}:#{session_id}")
  end

  # Convenience wrappers
  def self.cancel(session_id)  = set(session_id, type: "cancel")
  def self.redirect(session_id, message:) = set(session_id, type: "redirect", message:)
end
```

### Key Patterns

- **Namespaced keys** — `"session_signal:#{id}"` prevents collisions.
- **TTL** — always set an expiry as a safety net.
- **`getdel` for read-once semantics** — the signal is consumed the moment it's checked.
- **Class-level methods** — no instance state; purely functional interface.

---

## 14. ActionCable Integration

### Connection Auth

Authenticate via Warden (Devise) at the connection level:

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user || reject_unauthorized_connection
    end
  end
end
```

### Session-Scoped Channels

Validate the subscription and reject if the session doesn't exist:

```ruby
# app/channels/session_channel.rb
class SessionChannel < ApplicationCable::Channel
  def subscribed
    session = Session.find_by(id: params[:session_id])
    session ? stream_from("session_#{session.id}") : reject
  end
end
```

### Broadcasting from Jobs

Background jobs push events to the channel for real-time streaming:

```ruby
channel = "session_#{session.id}"
ActionCable.server.broadcast(channel, { type: "processing", active: true })

adapter.chat(messages:, options:) do |chunk|
  ActionCable.server.broadcast(channel, { type: "token", content: chunk[:content] })
end

ActionCable.server.broadcast(channel, { type: "done", content: full_content })
```

### Event Types Convention

Use a `type` key in every broadcast to let the frontend dispatch:

| Type | Purpose |
|------|---------|
| `processing` | Show/hide typing indicator |
| `token` | Streamed content chunk |
| `done` | Stream complete, includes full content |
| `error` | Something went wrong |
| `cancelled` | User cancelled the request |
| `redirected` | User redirected the agent mid-stream |
| `sub_agent_complete` | Sub-agent finished its task |
