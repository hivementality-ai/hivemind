# Upgrading Hivemind

## Versioning

Hivemind uses **CalVer** (Calendar Versioning): `YYYY.MM.PATCH`

- **YYYY.MM** — Year and month of the release
- **PATCH** — Sequential release number within that month

Examples: `2026.02.1`, `2026.02.2`, `2026.03.1`

Version is derived from GitHub tags and baked into Docker images at build time.

## Check Your Version

```bash
# Via API
curl http://localhost:3001/api/v1/system/version

# Via Rails console
docker compose exec rails rails runner "puts Hivemind::VERSION"
```

## Check for Updates

The version API checks GitHub Releases automatically:

```json
GET /api/v1/system/version

{
  "current": "2026.02.1",
  "latest": "2026.02.2",
  "update_available": true,
  "breaking_changes": false,
  "changelog_url": "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.2",
  "last_checked": "2026-02-17T15:00:00Z"
}
```

## Upgrade Steps

### Quick Upgrade

```bash
cd ~/hivemind    # or wherever you cloned it
git fetch --tags
git checkout main
git pull origin main
docker compose build
docker compose up -d
```

Migrations run automatically on container start.

### With Backup (Recommended)

```bash
cd ~/hivemind

# 1. Backup database
docker compose exec postgres pg_dump -U hivemind hivemind_production \
  > backups/pre-upgrade-$(date +%Y%m%d-%H%M%S).sql

# 2. Pull latest
git fetch --tags
git checkout main
git pull origin main

# 3. Rebuild and restart
docker compose build
docker compose up -d

# 4. Verify
curl http://localhost:3001/api/v1/system/version
```

### Pin a Specific Version

```bash
git fetch --tags
git checkout v2026.02.1
docker compose build
docker compose up -d
```

## Rollback

If an upgrade causes issues:

```bash
# 1. Stop containers
docker compose down

# 2. Checkout previous version
git checkout v2026.02.1

# 3. Restore database (if needed)
docker compose up -d postgres
docker compose exec postgres psql -U hivemind hivemind_production \
  < backups/pre-upgrade-YYYYMMDD-HHMMSS.sql

# 4. Rebuild and start
docker compose build
docker compose up -d
```

**Note:** Rollback only works if migrations are reversible. Check the release notes before upgrading.

## Breaking Changes

Breaking changes are flagged with ⚠️ in [Releases.md](../Releases.md). Always check the changelog before upgrading.

## Disable Update Checks

If you don't want Hivemind checking GitHub for new versions:

```env
# .env
UPDATE_CHECK_ENABLED=false
```

No data is sent to GitHub — it only reads the public Releases API. Disabling this means the version endpoint won't report available updates.

## Support Window

- **Active support:** Current month + previous month
- **Security fixes:** Up to 3 months back
- **EOL:** Older than 3 months — upgrade recommended
