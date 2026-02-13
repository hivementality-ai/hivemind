# Connectors Guide

Connectors bridge external messaging platforms to Hivemind. They run as sidecar services in Docker, receiving messages from platforms and forwarding them to Hivemind's webhook API.

## Architecture

```
┌──────────┐     ┌─────────────┐     ┌──────────────┐
│ WhatsApp │────▸│  Connector  │────▸│   Hivemind   │
│ Signal   │     │  (Node.js)  │◂────│   (Rails)    │
│ etc.     │◂────│  Port 3002  │     │   Port 3000  │
└──────────┘     └─────────────┘     └──────────────┘
     ▲                │                     │
     │           QR code in logs       Webhook POST
     │           Auth state in         /webhooks/:type
     │           Docker volume
     │                │
     └────────────────┘
        Replies sent back
        via connector API
```

**Flow:**
1. User sends a message on WhatsApp/Signal/etc.
2. Connector receives it and POSTs to `http://rails:3000/webhooks/whatsapp`
3. Hivemind routes the message to an agent
4. Agent processes and responds
5. Hivemind calls the connector's REST API to send the reply back

---

## Built-in Connectors

### WhatsApp (Baileys)

Uses [@whiskeysockets/baileys](https://github.com/WhiskeySockets/Baileys) to connect directly to WhatsApp Web. No Meta Business account required.

#### Setup

1. **Start the connector:**
   ```bash
   docker compose up connector
   ```

2. **Scan the QR code:**
   ```bash
   docker logs -f hivemind-connector-1
   ```
   A QR code will appear in the terminal. Scan it with WhatsApp on your phone:
   - Open WhatsApp → Settings → Linked Devices → Link a Device

3. **Create the channel in Hivemind:**
   Go to `/channels` → Add Channel:
   - **Name:** WhatsApp
   - **Platform:** WhatsApp
   - **Enabled:** ✅

   That's it. Messages will start flowing.

4. **Verify connection:**
   ```bash
   curl http://localhost:3002/health
   # {"status":"connected","user":"1234567890@s.whatsapp.net"}
   ```

#### Sending Messages

The connector exposes a REST API on port 3002:

```bash
# Send a text message
curl -X POST http://localhost:3002/send \
  -H "Content-Type: application/json" \
  -d '{"to": "+12175551234", "message": "Hello from Hivemind!"}'

# React to a message
curl -X POST http://localhost:3002/react \
  -H "Content-Type: application/json" \
  -d '{"to": "+12175551234", "messageId": "ABC123", "emoji": "👍"}'
```

#### Auth Persistence

WhatsApp auth state is stored in a Docker volume (`connector_auth`). You only need to scan the QR code once — it persists across container restarts.

To re-pair (if logged out):
```bash
docker volume rm hivemind_connector_auth
docker compose restart connector
# Scan new QR code
```

---

## Creating a Custom Connector

Connectors are simple HTTP bridges. You can write one in any language. Here's what you need:

### 1. Receive messages from the platform

Connect to the platform (WebSocket, polling, SDK, etc.) and listen for incoming messages.

### 2. Forward to Hivemind webhook

POST the message to Hivemind in the expected format:

```bash
POST http://rails:3000/webhooks/{channel_type}
Content-Type: application/json

# WhatsApp format:
{
  "entry": [{
    "changes": [{
      "value": {
        "messages": [{
          "id": "msg_123",
          "from": "+12175551234",
          "text": { "body": "Hello!" },
          "type": "text",
          "timestamp": 1707900000
        }],
        "metadata": {
          "phone_number_id": "connector"
        }
      }
    }]
  }]
}

# Telegram format:
{
  "message": {
    "message_id": 123,
    "from": { "id": 456, "first_name": "User" },
    "chat": { "id": 789, "type": "private" },
    "text": "Hello!",
    "date": 1707900000
  }
}

# Slack format:
{
  "event": {
    "type": "message",
    "user": "U123",
    "text": "Hello!",
    "channel": "C456",
    "ts": "1707900000.000000"
  },
  "team_id": "T789"
}

# Discord format:
{
  "id": "msg_123",
  "content": "Hello!",
  "author": { "id": "user_123" },
  "channel_id": "ch_456",
  "guild_id": "guild_789"
}

# Signal format (signal-cli):
{
  "envelope": {
    "source": "+12175551234",
    "sourceName": "User",
    "dataMessage": {
      "message": "Hello!",
      "timestamp": 1707900000
    }
  }
}
```

### 3. Expose a send endpoint

Hivemind's adapter will call your connector to send replies. Implement:

```
POST /send
Body: { "to": "recipient_id", "message": "text content" }
Response: { "status": "sent" }

GET /health
Response: { "status": "connected" }
```

### 4. Add to Docker Compose

```yaml
my_connector:
  build: ./connectors/my-platform
  depends_on:
    - rails
  environment:
    - HIVEMIND_URL=http://rails:3000
  networks:
    - internal
    - web
```

### 5. Create a Rails adapter

Add `app/services/channels/my_platform_adapter.rb`:

```ruby
module Channels
  class MyPlatformAdapter < BaseAdapter
    def receive(message)
      # Parse incoming webhook payload
      # Return ServiceResponse with :inbound_message
    end

    def send_message(to:, content:, **options)
      # POST to connector's /send endpoint
      # Return ServiceResponse with :outbound_message
    end

    def verify_webhook(request)
      # Verify webhook authenticity (or return true for internal connectors)
      true
    end
  end
end
```

### 6. Register in the channel registry

Add to `app/services/channels/registry.rb`:

```ruby
ADAPTERS = {
  # ... existing adapters
  "my_platform" => "Channels::MyPlatformAdapter"
}
```

### 7. Add to the Tool model validation

In `app/models/tool.rb`, update the executor_type inclusion list if needed.

### 8. Create the channel in the UI

Go to `/channels` → Add Channel with your platform type.

---

## Connector Configuration

Each channel's config is stored as JSON in the `channels` table. Common fields:

| Field | Description |
|-------|-------------|
| `connector_url` | URL of the connector sidecar (default: `http://connector:3002`) |
| `mode` | `connector` (default) or `cloud_api` for official APIs |
| `default_agent_id` | Agent to route messages to |
| `webhook_secret` | Secret for webhook signature verification |

---

## Webhook Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/webhooks/:channel_type` | Webhook verification (WhatsApp, Telegram) |
| `POST` | `/webhooks/:channel_type` | Incoming message handler |

Supported channel types: `whatsapp`, `telegram`, `discord`, `slack`, `signal`

---

## Tips

- **Auth persistence:** Use Docker volumes to store auth state across restarts
- **Internal networking:** Connectors talk to Rails over Docker's internal network — no need to expose Rails publicly
- **Multiple connectors:** Run one per platform, each on its own port
- **Rate limiting:** Hivemind uses Rack::Attack on webhook endpoints
- **Logging:** Check connector logs with `docker logs -f hivemind-connector-1`
- **Debugging:** Hit the `/health` endpoint to check connection status
