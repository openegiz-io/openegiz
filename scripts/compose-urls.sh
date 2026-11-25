#!/usr/bin/env bash
# Print where the compose stack can be reached and how to log in.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/compose-lib.sh
. "$ROOT/scripts/compose-lib.sh"

compose_resolve_profile "${1:-}"
# shellcheck disable=SC1091
set -a; . "$ROOT/deploy/compose/.env"; set +a

if [ "$PROFILE" = "prod" ]; then
  compose_prod_base_url
  cat <<TXT

OpenEgiz Production Profile is up (TLS: ${CADDY_TLS:-internal}).

  Grafana        $BASE_URL                     admin / $GRAFANA_ADMIN_PASSWORD
  Ditto API      $BASE_URL/ditto/api/2         ditto / $DITTO_PASSWORD   (devops / $DITTO_DEVOPS_PASSWORD)
  Ditto WS       wss://${DOMAIN}${PORT_SUFFIX}/ditto/ws/2
  3D Scene       $BASE_URL/build/<file>        (files from ./build/)
  MQTT           tcp://$DOMAIN:$MQTT_PORT  $MQTT_USERNAME / $MQTT_PASSWORD
TXT
  if [ "${MQTTS_ENABLED:-false}" = "true" ]; then
    printf '  MQTTS          ssl://%s:%s  %s / %s\n' "$DOMAIN" "${MQTTS_PORT:-8883}" "$MQTT_USERNAME" "$MQTT_PASSWORD"
  fi
  cat <<TXT

  Internal-only (no host ports): MongoDB, InfluxDB, Extended API.

Credentials live in deploy/compose/.env. Check everything with: make smoke
TXT
else
  H="${OPENEGIZ_PUBLIC_HOST:-localhost}"
  cat <<TXT

OpenEgiz is up.

  Grafana        http://$H:$GRAFANA_PORT        admin / $GRAFANA_ADMIN_PASSWORD
  Ditto API      http://$H:$DITTO_PORT/api/2    ditto / $DITTO_PASSWORD   (devops / $DITTO_DEVOPS_PASSWORD)
  Extended API   http://$H:$EXTENDED_API_PORT
  InfluxDB       http://$H:$INFLUXDB_PORT        admin / $INFLUXDB_ADMIN_PASSWORD
  MQTT           tcp://$H:$MQTT_PORT
  Unity WebGL    http://$H:$UNITY_PORT/build/<file>   (files from ./build/)

Credentials live in deploy/compose/.env. Check everything with: make smoke
TXT
fi
