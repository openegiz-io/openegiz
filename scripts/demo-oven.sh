#!/usr/bin/env bash
# Oven demo (examples/oven): create the two oven twins in Ditto, then stream
# telemetry over MQTT until Ctrl+C. Run via `make generate-data`.
#
# Compose (default): ports and credentials come from deploy/compose/.env.
#   Works with both the Dev Profile and the Production Profile (`make up-prod`).
# Helm: pass them explicitly, e.g.
#   make generate-data MQTT_PORT=30511 DITTO_URL=http://localhost:30525 DITTO_PASSWORD=...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/compose-lib.sh
. "$ROOT/scripts/compose-lib.sh"

ENV_FILE="$ROOT/deploy/compose/.env"
VENV="$ROOT/examples/.venv"
compose_resolve_profile "${1:-}"

# Caller-provided values win over deploy/compose/.env.
caller_mqtt_host="${MQTT_HOST:-}"
caller_mqtt_port="${MQTT_PORT:-}"
caller_mqtt_user="${MQTT_USERNAME:-}"
caller_mqtt_pass="${MQTT_PASSWORD:-}"
caller_ditto_url="${DITTO_URL:-}"
caller_ditto_password="${DITTO_PASSWORD:-}"
caller_ditto_ca_cert="${DITTO_CA_CERT:-}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

MQTT_HOST="${caller_mqtt_host:-localhost}"
MQTT_PORT="${caller_mqtt_port:-${MQTT_PORT:-1883}}"
DITTO_PASSWORD="${caller_ditto_password:-${DITTO_PASSWORD:-}}"
DITTO_CA_CERT="${caller_ditto_ca_cert:-}"

CA_TMP=""
cleanup() {
  [ -n "$CA_TMP" ] && rm -f "$CA_TMP" || true
}
trap cleanup EXIT

if [ "$PROFILE" = "prod" ]; then
  compose_build_args
  compose_prod_base_url
  DITTO_URL="${caller_ditto_url:-${BASE_URL}/ditto}"
  MQTT_USERNAME="${caller_mqtt_user:-${MQTT_USERNAME:-}}"
  MQTT_PASSWORD="${caller_mqtt_pass:-${MQTT_PASSWORD:-}}"
  if [ -z "$DITTO_CA_CERT" ] && [ "${CADDY_TLS:-internal}" = "internal" ] && [ -z "$caller_ditto_url" ]; then
    CA_TMP="$(mktemp)"
    if ! compose_extract_caddy_ca "$CA_TMP" 20; then
      echo "ERROR: could not read Caddy local root CA from caddy container." >&2
      exit 1
    fi
    DITTO_CA_CERT="$CA_TMP"
  fi
else
  DITTO_URL="${caller_ditto_url:-http://localhost:${DITTO_PORT:-8080}}"
  MQTT_USERNAME="${caller_mqtt_user:-}"
  MQTT_PASSWORD="${caller_mqtt_pass:-}"
fi

if [ -z "$DITTO_PASSWORD" ]; then
  echo "ERROR: no Ditto password. Start the platform with 'make up' (or 'make up-prod') first," >&2
  echo "       or pass DITTO_PASSWORD=... (Helm deployments)." >&2
  exit 1
fi

if [ ! -x "$VENV/bin/python" ]; then
  echo "==> creating $VENV (first run only)"
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --disable-pip-version-check -r "$ROOT/examples/requirements.txt"

echo "==> oven twins in Ditto ($DITTO_URL)"
DITTO_URL="$DITTO_URL" DITTO_PASSWORD="$DITTO_PASSWORD" DITTO_CA_CERT="$DITTO_CA_CERT" \
  TWINS_FILE="$ROOT/examples/oven/twins.json" \
  "$VENV/bin/python" "$ROOT/examples/mine/setup_twins.py"

# Remove temp CA file before exec replaces this shell (EXIT trap will not fire).
if [ -n "$CA_TMP" ]; then
  rm -f "$CA_TMP"
  CA_TMP=""
fi

gen_args=(--mqtt-host "$MQTT_HOST" --mqtt-port "$MQTT_PORT")
if [ -n "$MQTT_USERNAME" ]; then
  gen_args+=(--mqtt-username "$MQTT_USERNAME" --mqtt-password "$MQTT_PASSWORD")
fi

echo "==> streaming oven telemetry to MQTT $MQTT_HOST:$MQTT_PORT (Ctrl+C to stop)"
exec "$VENV/bin/python" "$ROOT/examples/oven/data_generator.py" "${gen_args[@]}"
