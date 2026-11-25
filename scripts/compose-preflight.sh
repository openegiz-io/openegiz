#!/usr/bin/env bash
#
# Catch the usual first-run problems before `docker compose up` turns them
# into cryptic container errors: Docker not running, an old Compose, too
# little memory for Docker, host ports already taken, missing MQTTS certs.
#
# Pass --prod (or set OPENEGIZ_PROFILE=prod) for Production Profile checks.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/compose-lib.sh
. "$ROOT/scripts/compose-lib.sh"

PROFILE="${OPENEGIZ_PROFILE:-dev}"
[ "${1:-}" = "--prod" ] && PROFILE="prod"

# shellcheck disable=SC1091
set -a; . "$ROOT/deploy/compose/.env"; set +a

die() { printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$1" >&2; }

docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop, or the docker service on Linux)."

compose_version="$(docker compose version --short 2>/dev/null || true)"
compose_version="${compose_version#v}"
[ -n "$compose_version" ] || die "Docker Compose v2 is required ('docker compose', not 'docker-compose')."
major="${compose_version%%.*}"
rest="${compose_version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
patch="${patch%%[^0-9]*}"
patch="${patch:-0}"

if [ "$PROFILE" = "prod" ] || [ -n "${OPENEGIZ_RELEASE:-}" ]; then
  if [ "$major" -lt 2 ] || \
     { [ "$major" -eq 2 ] && [ "$minor" -lt 24 ]; } || \
     { [ "$major" -eq 2 ] && [ "$minor" -eq 24 ] && [ "$patch" -lt 4 ]; }; then
    die "Docker Compose $compose_version is too old for the Production Profile or release images; 2.24.4 or newer is required."
  fi
else
  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 20 ]; }; then
    die "Docker Compose $compose_version is too old; 2.20 or newer is required."
  fi
fi

mem_bytes="$(docker info --format '{{.MemTotal}}')"
mem_gib=$((mem_bytes / 1024 / 1024 / 1024))
if [ "$mem_gib" -lt 6 ]; then
  warn "Docker has ${mem_gib} GiB of memory; OpenEgiz needs about 6 GiB. Raise it in Docker Desktop -> Settings -> Resources."
fi

if [ "$PROFILE" = "prod" ] && [ "${MQTTS_ENABLED:-false}" = "true" ]; then
  certs_dir="${MQTTS_CERTS_DIR:-$ROOT/deploy/compose/mosquitto/certs}"
  case "$certs_dir" in
    /*) ;;
    *) certs_dir="$ROOT/deploy/compose/$certs_dir" ;;
  esac
  for cert_name in ca.crt server.crt server.key; do
    if [ ! -r "$certs_dir/$cert_name" ]; then
      die "MQTTS_ENABLED=true but missing readable TLS file: $certs_dir/$cert_name"
    fi
  done
fi

# True if something accepts connections on 127.0.0.1:$1. Gives up after ~2 s
# and treats the port as free: with WSL mirrored networking a connect to an
# unused port hangs until the TCP timeout instead of being refused. Plain bash
# rather than `timeout`, which macOS does not ship.
port_busy() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null &
  local pid=$!
  for _ in $(seq 20); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return
    fi
    sleep 0.1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 1
}

compose_build_args

# A port is a problem only if something other than this stack holds it.
ours="$("${COMPOSE[@]}" ps -q 2>/dev/null || true)"
if [ -z "$ours" ]; then
  if [ "$PROFILE" = "prod" ]; then
    vars=(HTTP_PORT HTTPS_PORT MQTT_PORT)
    if [ "${MQTTS_ENABLED:-false}" = "true" ]; then
      vars+=(MQTTS_PORT)
    fi
  else
    vars=(GRAFANA_PORT DITTO_PORT EXTENDED_API_PORT UNITY_PORT INFLUXDB_PORT MQTT_PORT)
  fi
  busy=()
  for var in "${vars[@]}"; do
    port="${!var:-}"
    if [ -n "$port" ] && port_busy "$port"; then
      busy+=("$var=$port")
    fi
  done
  if [ "${#busy[@]}" -gt 0 ]; then
    die "Ports already in use on this machine: ${busy[*]}. Stop whatever uses them, or change these values in deploy/compose/.env."
  fi
fi
