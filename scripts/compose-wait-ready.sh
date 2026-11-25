#!/usr/bin/env bash
#
# Ditto's services report healthy before the cluster has finished placing its
# shards, and for a while after that REST calls still fail. `make up` and
# `make up-prod` should only return once the platform actually serves requests,
# so wait for a run of consecutive successful reads.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/compose-lib.sh
. "$ROOT/scripts/compose-lib.sh"

compose_resolve_profile "${1:-}"
# shellcheck disable=SC1091
set -a; . "$ROOT/deploy/compose/.env"; set +a
compose_build_args

CURL_ARGS=(-sf -o /dev/null)
CA_CERT=""
cleanup() {
  [ -n "$CA_CERT" ] && rm -f "$CA_CERT" || true
}
trap cleanup EXIT

if [ "$PROFILE" = "prod" ]; then
  compose_prod_base_url
  DITTO="${BASE_URL}/ditto"
  CURL_ARGS+=(--resolve "${DOMAIN}:${HTTPS_PORT}:127.0.0.1")

  if [ "${CADDY_TLS:-internal}" = "internal" ]; then
    CA_CERT="$(mktemp)"
    if ! compose_extract_caddy_ca "$CA_CERT" 30; then
      echo "ERROR: could not read Caddy local root CA from caddy container." >&2
      exit 1
    fi
    CURL_ARGS+=(--cacert "$CA_CERT")
  fi
else
  DITTO="http://127.0.0.1:$DITTO_PORT"
fi

needed=5
streak=0
deadline=$((SECONDS + 300))

printf 'Waiting for Ditto to serve requests '
while [ "$streak" -lt "$needed" ]; do
  if curl "${CURL_ARGS[@]}" -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/policies/default:basic_policy" \
     && curl "${CURL_ARGS[@]}" -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/search/things?option=size(1)"; then
    streak=$((streak + 1))
  else
    streak=0
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo
    echo "ERROR: Ditto did not start serving requests within 5 minutes." >&2
    echo "       Inspect with: make logs S=gateway" >&2
    exit 1
  fi
  printf '.'
  sleep 2
done
echo " ready"
