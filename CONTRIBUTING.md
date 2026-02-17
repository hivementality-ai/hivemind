# Contributing to Hivemind 🐝

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/hivemind.git`
3. Run the install script: `./install.sh`
4. Create a branch: `git checkout -b feat/your-feature`

## Branch Naming

Use prefixed branch names:

| Prefix | Use for | Example |
|--------|---------|---------|
| `feat/` | New features | `feat/slack-threads` |
| `fix/` | Bug fixes | `fix/streaming-disconnect` |
| `docs/` | Documentation | `docs/api-guide` |
| `refactor/` | Code cleanup | `refactor/tool-executor` |
| `test/` | Test coverage | `test/agent-model-specs` |

## Pull Requests

**All changes go through PRs** — direct pushes to `main` are blocked.

### PR Requirements

1. **Descriptive title** — use conventional commit format:
   - `feat: add Slack thread routing`
   - `fix: streaming disconnect on long responses`
   - `docs: add API authentication guide`

2. **Complete PR description** — use the PR template. Every PR must include:
   - **What's new** — what the PR does in plain language
   - **How it works** — your approach and key decisions
   - **Files changed** — list main files and what each change does
   - **Testing** — how you verified it works
   - **Screenshots** — for any UI changes
   - **Breaking changes** — flag if applicable

3. **Focused scope** — one feature or fix per PR. Don't mix unrelated changes.

4. **Tests** — add specs for new features. Run existing specs before pushing:
   ```bash
   docker compose exec rails bundle exec rspec
   ```

### PR Review

- PRs require **1 approval** before merging
- Stale approvals are dismissed when new commits are pushed
- Address review feedback with new commits (don't force-push during review)

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add agent thinking budget controls
fix: prevent duplicate team chat messages
docs: update Docker setup instructions
test: add controller specs for sessions
refactor: extract tool executor into service object
```

For multi-line commits:

```
feat: markdown rendering in chat messages

- Add marked.js via importmap CDN pin
- Parse streamed agent responses as markdown on stream finish
- Style code blocks, tables, blockquotes for dark theme
```

## Code Style

- **Ruby:** Follow Rails conventions. Use service objects for business logic.
- **JavaScript:** Stimulus controllers. Keep them focused.
- **CSS:** Tailwind utility classes. Custom CSS in `application.css` only when needed.
- **Views:** ERB templates. Keep logic minimal — use helpers and partials.

## Database Migrations

- **Add columns** with defaults when possible
- **Never remove columns** in the same PR — deprecate first
- **Test migrations** locally before pushing:
  ```bash
  docker compose exec rails rails db:migrate
  docker compose exec rails rails db:rollback STEP=1
  docker compose exec rails rails db:migrate
  ```

## Questions?

- Open a [Discussion](https://github.com/hivementality-ai/hivemind/discussions)
- Join our [Discord](https://discord.gg/Cww4rFz7)
