#!/usr/bin/env bash
# Shared helper functions for OpenEgiz Docker Compose scripts (Dev and Production Profiles).
# Source this file after setting ROOT to the repository root.

compose_resolve_profile() {
  local arg="${1:-}"
  PROFILE="${OPENEGIZ_PROFILE:-dev}"
  if [ "$arg" = "--prod" ] || [ -f "$ROOT/deploy/compose/.prod" ]; then
    PROFILE="prod"
  fi
}

compose_build_args() {
  COMPOSE=(docker compose -f "$ROOT/deploy/compose/docker-compose.yml")
  if [ "$PROFILE" = "prod" ]; then
    COMPOSE+=(-f "$ROOT/deploy/compose/docker-compose.prod.yml")
    if [ "${MQTTS_ENABLED:-false}" = "true" ]; then
      COMPOSE+=(-f "$ROOT/deploy/compose/docker-compose.mqtts.yml")
    fi
  fi
}

compose_prod_base_url() {
  DOMAIN="${OPENEGIZ_DOMAIN:-localhost}"
  # shellcheck disable=SC2034
  HTTP_PORT="${HTTP_PORT:-80}"
  HTTPS_PORT="${HTTPS_PORT:-443}"
  PORT_SUFFIX=""
  if [ "$HTTPS_PORT" != "443" ]; then
    PORT_SUFFIX=":$HTTPS_PORT"
  fi
  # shellcheck disable=SC2034
  BASE_URL="https://${DOMAIN}${PORT_SUFFIX}"
}

compose_extract_caddy_ca() {
  local dest="$1"
  local attempts="${2:-30}"
  local _i
  for _i in $(seq 1 "$attempts"); do
    if "${COMPOSE[@]}" exec -T caddy cat /data/caddy/pki/authorities/local/root.crt >"$dest" 2>/dev/null && [ -s "$dest" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}
