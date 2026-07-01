# Scope the session cookie name to this instance so multiple Hivemind
# instances can coexist on one host. Browsers share cookies across ports
# for the same host (localhost:8080 and localhost:8081 share a jar), so a
# shared cookie name would let instances overwrite each other's session —
# producing "Can't verify CSRF token authenticity" 422s on sign-in.
#
# COMPOSE_PROJECT_NAME is unique per instance ("hivemind" for the primary,
# "hivemind-<name>" for instances created via `hivemind new`). The primary
# keeps the historical "_hivemind_session" key via the default fallback, so
# existing sessions are not invalidated.
Rails.application.config.session_store :cookie_store,
  key: "_#{ENV.fetch('COMPOSE_PROJECT_NAME', 'hivemind')}_session"
