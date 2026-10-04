#!/usr/bin/env bash
# Runs on the VPS as the admin user, from ~/openclaw. Idempotent: re-running
# refreshes .env and the image, and only onboards when no config exists yet.
set -euo pipefail

cd "$(dirname "$0")"

STATE_DIR="$HOME/.openclaw"
SECRET_DIR="$HOME/.openclaw-auth-profile-secrets"

log() { printf '\n==> %s\n' "$*"; }

# Pre-start CLI, only safe while the gateway is stopped.
cli() {
  docker compose run --rm --no-deps -T --entrypoint node openclaw-gateway dist/index.js "$@"
}

log "Writing .env"
umask 077
token="$(grep -s '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d= -f2- || true)"
[[ -n "$token" ]] || token="$(openssl rand -hex 32)"
{
  cat secrets.env
  echo "OPENCLAW_CONFIG_DIR=$STATE_DIR"
  echo "OPENCLAW_WORKSPACE_DIR=$STATE_DIR/workspace"
  echo "OPENCLAW_AUTH_PROFILE_SECRET_DIR=$SECRET_DIR"
  echo "OPENCLAW_GATEWAY_TOKEN=$token"
} >.env.new
mv .env.new .env
rm -f secrets.env
umask 022

# The container runs as node (uid 1000); the admin user is created with the
# same uid so these bind mounts are writable without a chown pass.
mkdir -p "$STATE_DIR/workspace" "$SECRET_DIR"
chmod 700 "$STATE_DIR" "$SECRET_DIR"

log "Pulling image"
docker compose pull openclaw-gateway

# The one-off CLI containers below must never share the state dir with a
# running gateway: they would take over its state lock.
docker compose stop openclaw-gateway 2>/dev/null || true

if [[ -f "$STATE_DIR/openclaw.json" ]]; then
  log "Existing config found, skipping onboarding"
else
  log "Onboarding"
  # Secrets stay in .env; the config only holds env references to them.
  cli onboard --non-interactive --accept-risk \
    --mode local \
    --no-install-daemon \
    --auth-choice deepseek-api-key \
    --secret-input-mode ref \
    --gateway-auth token \
    --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --skip-ui \
    --skip-health \
    --skip-skills \
    --suppress-gateway-token-output
fi

log "Pinning gateway config"
cli config set --batch-json '[
  {"path":"gateway.mode","value":"local"},
  {"path":"gateway.bind","value":"lan"},
  {"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789"]}
]' >/dev/null

log "Configuring Telegram"
TELEGRAM_BOT_TOKEN="$(grep '^TELEGRAM_BOT_TOKEN=' .env | cut -d= -f2-)"
cli channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"

log "Starting gateway"
docker compose up -d openclaw-gateway

for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
    echo "Gateway is healthy."
    exit 0
  fi
  sleep 2
done

echo "Gateway did not become healthy within 2 minutes. Recent logs:" >&2
docker compose logs --tail 50 openclaw-gateway >&2
exit 1
