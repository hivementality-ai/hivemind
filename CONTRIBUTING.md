# Contributing to Hivemind

Thanks for your interest in contributing! Here's everything you need to get started.

---

## Getting Started

1. Fork the repo
2. Clone your fork
3. Create a feature branch (`git checkout -b feat/my-feature`)
4. Make your changes
5. Run the test suite
6. Open a PR with a clear description

---

## Development Setup

**Prerequisites:** Docker Desktop (or Docker Engine + Compose v2)

```bash
git clone https://github.com/MatthewSuttles/hivemind.git
cd hivemind
cp .env.example .env
docker compose up -d
```

Open **http://localhost:3001** and run through the setup wizard.

### Running Tests

Tests run inside the Docker container against a test database:

```bash
docker compose exec app bash -c "RAILS_ENV=test bundle exec rspec"
```

Coverage report is generated automatically via SimpleCov.

---

## Code Standards

### Rails

- **Skinny controllers** — HTTP orchestration only. Parse params, authorize, call a service, render.
- **Service objects** — All business logic lives in `app/services/`. Keyword args, return values.
- **Models** — Associations, validations, scopes, and simple domain logic only. No HTTP, no side effects.
- **Concerns** — Shared behavior with clear single responsibility.
- **Explicit over implicit** — Readability and clarity always win.

### Testing (RSpec)

- **95% overall coverage**, 100% on new/modified code
- **90% branch coverage**
- Test the **public interface** only — never test private methods
- Use `describe` / `context` / `it` structure
- FactoryBot with traits. Prefer `build` over `create` when persistence isn't needed
- Mock external dependencies (APIs, Docker, HTTP). Don't mock ActiveRecord or internal app logic
- One logical assertion per `it` block when practical
- Descriptive test names that explain intent
- **No Capybara/system tests, no JS tests, no view tests**

### Style

- Use `expect(...).to` syntax (not `should`)
- `let` over instance variables
- `instance_double` for stub contracts
- Run specs with `--order random` to surface order dependencies

---

## Architecture

### Docker Stack

| Service | Purpose |
|---------|---------|
| **app** | Rails + Puma (HTTP, WebSocket, API) |
| **worker** | Sidekiq background jobs |
| **db** | PostgreSQL with pgvector |
| **cache** | Redis (queues + pub/sub + caching) |
| **browser** | Playwright headless Chrome |
| **workspace** | Isolated exec sandbox for agents |
| **connector** | Persistent channel connections (WhatsApp, Signal) |
| **docker-proxy** | socat proxy for workspace container access |

### Key Directories

```
app/
├── controllers/     # HTTP layer
├── models/          # ActiveRecord + domain logic
├── services/        # Business logic (agents/, tools/, channels/, etc.)
├── jobs/            # Sidekiq background jobs
└── views/           # ERB templates (Tailwind CSS)

spec/
├── models/          # Model specs
├── controllers/     # Request/controller specs
├── services/        # Service specs
└── sidekiq/         # Job specs
```

### Adding a New Tool

1. Create `app/services/tools/my_tool_executor.rb` inheriting from `Tools::BaseExecutor`
2. Implement the `call` method (receives `agent:`, `session:`, `params:`)
3. Return `{ output: "result" }` or `{ error: "message" }`
4. Add a seed entry in `db/seeds/tools.rb`
5. Write specs in `spec/services/tools/my_tool_executor_spec.rb`

### Adding a New Channel

1. Create `app/services/channels/my_adapter.rb` inheriting from `Channels::BaseAdapter`
2. Implement `send_message` and `verify_webhook`
3. Register in `app/services/channels/registry.rb`
4. Add webhook route and controller action
5. Write specs

---

## PR Guidelines

- Keep PRs focused — one feature or fix per PR
- Include tests for all new code
- Update docs if behavior changes
- Use conventional commit style: `feat:`, `fix:`, `docs:`, `test:`, `chore:`

---

## License

By contributing, you agree that your contributions will be licensed under the [AGPLv3](LICENSE).
