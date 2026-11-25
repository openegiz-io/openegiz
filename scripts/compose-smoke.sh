#!/usr/bin/env bash
#
# End-to-end check of a running compose stack (Dev or Production Profile).
# Exercises the full loop the platform exists for:
#   MQTT (Ditto protocol) -> Ditto twin -> MQTT event -> Telegraf -> InfluxDB
# plus Grafana provisioning, the Extended API, the 3D Scene server, and
# Reference Examples. In Production Profile (--prod or deploy/compose/.prod),
# also verifies Caddy HTTPS/TLS routing (Grafana, Ditto HTTP/WS, 3D Scene),
# HTTP->HTTPS redirect, MQTT authentication (anonymous rejection + auth success),
# and closed host ports for storage and backend services.
# Leaves nothing behind: test twins are deleted at the end.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/compose-lib.sh
. "$ROOT/scripts/compose-lib.sh"

compose_resolve_profile "${1:-}"

# shellcheck disable=SC1091
set -a; . "$ROOT/deploy/compose/.env"; set +a

compose_build_args
compose_prod_base_url

HOST=127.0.0.1

CURL_TLS_ARGS=()
CA_CERT=""
MQTT_CLI_AUTH=()

if [ "$PROFILE" = "prod" ]; then
  DITTO="${BASE_URL}/ditto"
  GRAFANA="${BASE_URL}"
  UNITY_URL="${BASE_URL}/build/README.md"
  CURL_TLS_ARGS+=(--resolve "${DOMAIN}:${HTTPS_PORT}:127.0.0.1")
  MQTT_CLI_AUTH=(-u "$MQTT_USERNAME" -P "$MQTT_PASSWORD")
else
  DITTO="http://$HOST:$DITTO_PORT"
  GRAFANA="http://$HOST:$GRAFANA_PORT"
  UNITY_URL="http://$HOST:$UNITY_PORT/build/README.md"
fi

THING="org.openegiz:smoke-test-$$"
OVEN_CLEANUP=()
FAILED=0

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILED=1; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

curl_get() { curl ${CURL_TLS_ARGS[@]+"${CURL_TLS_ARGS[@]}"} -sf "$@"; }
curl_grep() { local pat="$1"; shift; curl_get "$@" | grep -q "$pat"; }

# For reads from Ditto: right after start, while its JVMs warm up and the
# Example Mine simulator starts, Ditto answers 503 "Please retry" for a few
# seconds at a time. Retry for up to a minute before calling it a failure.
check_ditto() {
  local name="$1"; shift
  for _ in $(seq 1 20); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return; fi
    sleep 3
  done
  fail "$name"
}

wait_influx() {
  local flux="$1" pattern="$2" pass_msg="$3" fail_msg="$4"
  for _ in $(seq 1 30); do
    if "${COMPOSE[@]}" exec -T influxdb influx query --org openegiz --token "$INFLUXDB_TOKEN" --raw "$flux" 2>/dev/null \
        | grep -qE "$pattern"; then
      pass "$pass_msg"
      return
    fi
    sleep 2
  done
  fail "$fail_msg"
}

run_oven_generator() {
  local py=""
  local extra_args=()
  if [ "$PROFILE" = "prod" ]; then
    extra_args+=(--mqtt-username "$MQTT_USERNAME" --mqtt-password "$MQTT_PASSWORD")
  fi
  if python3 -c "import paho.mqtt.client as m; assert hasattr(m, 'CallbackAPIVersion')" >/dev/null 2>&1; then
    py="python3"
  elif [ -x "$ROOT/examples/.venv/bin/python" ] && \
       "$ROOT/examples/.venv/bin/python" -c "import paho.mqtt.client as m; assert hasattr(m, 'CallbackAPIVersion')" >/dev/null 2>&1; then
    py="$ROOT/examples/.venv/bin/python"
  elif docker image inspect openegiz/example-mine:local >/dev/null 2>&1; then
    docker run --rm --network openegiz_default -v "$ROOT/examples/oven:/oven:ro" \
      openegiz/example-mine:local python /oven/data_generator.py --mqtt-host mosquitto --mqtt-port 1883 ${extra_args[@]+"${extra_args[@]}"} --steps 1 >/dev/null 2>&1
    return $?
  else
    python3 -m venv "$ROOT/examples/.venv" >/dev/null 2>&1 && \
      "$ROOT/examples/.venv/bin/pip" install --quiet --disable-pip-version-check -r "$ROOT/examples/requirements.txt" >/dev/null 2>&1 || return 1
    py="$ROOT/examples/.venv/bin/python"
  fi
  "$py" "$ROOT/examples/oven/data_generator.py" --mqtt-host "$HOST" --mqtt-port "$MQTT_PORT" ${extra_args[@]+"${extra_args[@]}"} --steps 1 >/dev/null 2>&1
}

container_has_host_ports() {
  local svc="$1" cid
  cid="$("${COMPOSE[@]}" ps -q "$svc")"
  [ -n "$cid" ] || return 0
  python3 -c '
import json, subprocess, sys
out = subprocess.check_output(["docker", "inspect", "--format", "{{json .NetworkSettings.Ports}}", sys.argv[1]], text=True)
ports = json.loads(out) or {}
bound = [k for k, v in ports.items() if v]
sys.exit(0 if bound else 1)
' "$cid"
}

tcp_port_open() {
  python3 -c '
import socket, sys
s = socket.socket()
s.settimeout(1.0)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
' "$1"
}

check_http_redirect() {
  local hdrs
  hdrs="$(curl -sS -I --max-time 5 -H "Host: $DOMAIN" "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null || true)"
  printf '%s' "$hdrs" | grep -qiE '^HTTP/[0-9.]+ 30[18]' && printf '%s' "$hdrs" | grep -qiE '^location: https://'
}

check_ditto_ws() {
  local first_line
  first_line="$(curl ${CURL_TLS_ARGS[@]+"${CURL_TLS_ARGS[@]}"} --http1.1 -sS -i --max-time 2 \
    -u "ditto:$DITTO_PASSWORD" \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    "$DITTO/ws/2" 2>/dev/null | head -n 1 || true)"
  printf '%s' "$first_line" | grep -q "101"
}

cleanup() {
  curl ${CURL_TLS_ARGS[@]+"${CURL_TLS_ARGS[@]}"} -s -o /dev/null -u "ditto:$DITTO_PASSWORD" -X DELETE "$DITTO/api/2/things/$THING" || true
  for oven_id in ${OVEN_CLEANUP[@]+"${OVEN_CLEANUP[@]}"}; do
    curl ${CURL_TLS_ARGS[@]+"${CURL_TLS_ARGS[@]}"} -s -o /dev/null -u "ditto:$DITTO_PASSWORD" -X DELETE "$DITTO/api/2/things/$oven_id" || true
  done
  [ -n "$CA_CERT" ] && rm -f "$CA_CERT" || true
}
trap cleanup EXIT

if [ "$PROFILE" = "prod" ] && [ "${CADDY_TLS:-internal}" = "internal" ]; then
  CA_CERT="$(mktemp)"
  if compose_extract_caddy_ca "$CA_CERT" 20; then
    CURL_TLS_ARGS+=(--cacert "$CA_CERT")
  else
    fail "could not extract Caddy local root CA"
  fi
fi

echo "Profile: $PROFILE"
echo "Containers"
init_exit=$("${COMPOSE[@]}" ps -a --format '{{.Service}} {{.ExitCode}}' | awk '$1=="init"{print $2}')
if [ "$init_exit" = "0" ]; then pass "init job finished (policy + connections)"; else fail "init job exit code: ${init_exit:-not run}"; fi
# The Plugin Bundle init container must have copied both plugins and exited.
plugins_exit=$("${COMPOSE[@]}" ps -a --format '{{.Service}} {{.ExitCode}}' | awk '$1=="grafana-plugins"{print $2}')
if [ "$plugins_exit" = "0" ]; then pass "plugin bundle image installed the plugins"; else fail "grafana-plugins init exit code: ${plugins_exit:-not run}"; fi
unhealthy=$("${COMPOSE[@]}" ps --format '{{.Service}} {{.Health}}' | awk '$2!="" && $2!="healthy"{print $1}')
if [ -z "$unhealthy" ]; then pass "all health-checked services healthy"; else fail "not healthy: $(echo "$unhealthy")"; fi

if [ "$PROFILE" = "prod" ]; then
  echo "Production TLS & Network Isolation"
  check "HTTP ($HTTP_PORT) redirects to HTTPS" check_http_redirect
  check_ditto "Ditto WebSocket (/ditto/ws/2) upgrades over HTTPS" check_ditto_ws
  for svc in mongodb influxdb extended-api grafana ditto-nginx unity; do
    if container_has_host_ports "$svc"; then
      fail "$svc has published host ports in Production Profile"
    else
      pass "$svc publishes no host ports"
    fi
  done
  for pair in "mongodb:27017" "influxdb:$INFLUXDB_PORT" "extended-api:$EXTENDED_API_PORT"; do
    svc="${pair%%:*}"
    port="${pair#*:}"
    if tcp_port_open "$port"; then
      fail "$svc host port $port is unexpectedly accepting connections"
    else
      pass "$svc host port $port is closed"
    fi
  done

  echo "Production MQTT Auth"
  anon_pub_out="$("${COMPOSE[@]}" exec -T mosquitto mosquitto_pub -h localhost -t telemetry/anon-smoke -m '{}' 2>&1)" && anon_pub_rc=0 || anon_pub_rc=$?
  if [ "$anon_pub_rc" -ne 0 ] && printf '%s' "$anon_pub_out" | grep -qi 'not authori'; then
    pass "anonymous MQTT publish rejected (not authorised)"
  else
    fail "anonymous MQTT publish was not rejected by auth (rc=$anon_pub_rc: $anon_pub_out)"
  fi
  # Subscribe to retained $SYS/broker/version so an erroneously allowed anonymous
  # client would receive a message immediately rather than timing out.
  anon_sub_out="$("${COMPOSE[@]}" exec -T mosquitto mosquitto_sub -h localhost -t '$SYS/broker/version' -C 1 -W 5 2>&1)" && anon_sub_rc=0 || anon_sub_rc=$?
  if [ "$anon_sub_rc" -ne 0 ] && printf '%s' "$anon_sub_out" | grep -qi 'not authori'; then
    pass "anonymous MQTT subscribe rejected (not authorised)"
  else
    fail "anonymous MQTT subscribe was not rejected by auth (rc=$anon_sub_rc: $anon_sub_out)"
  fi
fi

echo "Ditto"
check_ditto "status/health is UP" curl_grep '"UP"' -u "devops:$DITTO_DEVOPS_PASSWORD" "$DITTO/status/health"
check_ditto "default policy exists" curl_get -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/policies/default:basic_policy"
for c in mosquitto-source-connection mosquitto-target-connection; do
  check_ditto "connection $c open" curl_grep '"open"' -u "devops:$DITTO_DEVOPS_PASSWORD" "$DITTO/api/2/connections/$c/status"
done
check_ditto "create test twin" curl_get -u "ditto:$DITTO_PASSWORD" -X PUT -H 'Content-Type: application/json' \
  -d '{"policyId":"default:basic_policy","features":{"smoke":{"properties":{"value":0}}}}' "$DITTO/api/2/things/$THING"

# Each Ditto JVM needs about 300 MiB besides its heap (metaspace, JIT code, GC
# structures, threads), more as it runs; the compose file gives it 512. With
# less room the kernel kills the JVM once the heap has grown under load,
# 5-60 minutes into a run (docker reports exit 137 and OOMKilled=false). The heap size comes from the JVM itself, so
# this also catches a JVM that cannot see its container limit and sizes the
# heap from the host's memory (JDK 17.0.8 on kernels without the cgroup v1
# memory controller, such as the 6.12 kernel of recent Docker Desktop).
echo "Ditto memory"
for svc in policies things things-search connectivity gateway; do
  heap="" limit=""
  for _ in 1 2 3; do
    heap=$("${COMPOSE[@]}" exec -T "$svc" curl -s -m 5 localhost:9095/ 2>/dev/null \
      | awk '/^jvm_memory_max_bytes\{region="heap"/ {printf "%d", $2 / 1048576}') || true
    [ -n "$heap" ] && break
    sleep 3
  done
  limit=$("${COMPOSE[@]}" exec -T "$svc" sh -c 'cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes' 2>/dev/null \
    | awk '/^[0-9]+$/ {printf "%d", $1 / 1048576}') || true
  if [ -z "$heap" ] || [ -z "$limit" ]; then
    fail "$svc: could not read max heap (${heap:-?} MiB) or container limit (${limit:-?} MiB)"
  elif [ $((limit - heap)) -ge 512 ]; then
    pass "$svc: max heap ${heap} MiB leaves $((limit - heap)) MiB of its ${limit} MiB limit"
  else
    fail "$svc: max heap ${heap} MiB leaves $((limit - heap)) MiB of its ${limit} MiB limit (need 512)"
  fi
done

echo "Telemetry loop"
value=$((RANDOM % 1000 + 1))
msg=$(printf '{"topic":"%s/%s/things/twin/commands/modify","path":"/features/smoke/properties/value","value":%s}' \
  "${THING%%:*}" "${THING#*:}" "$value")
# Capture the twin event Ditto publishes back, to check what it exposes.
event_file="$(mktemp)"
"${COMPOSE[@]}" exec -T mosquitto mosquitto_sub -h localhost ${MQTT_CLI_AUTH[@]+"${MQTT_CLI_AUTH[@]}"} -C 1 -W 30 \
  -t "openegiz/twin/events/${THING%%:*}/${THING#*:}" >"$event_file" 2>/dev/null &
sub_pid=$!
sleep 1
"${COMPOSE[@]}" exec -T mosquitto mosquitto_pub -h localhost ${MQTT_CLI_AUTH[@]+"${MQTT_CLI_AUTH[@]}"} -t telemetry/smoke -m "$msg"

ok=0
for _ in $(seq 1 15); do
  got=$(curl_get -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/things/$THING/features/smoke/properties/value" || true)
  if [ "$got" = "$value" ]; then ok=1; break; fi
  sleep 1
done
if [ $ok = 1 ]; then pass "MQTT -> Ditto updated the twin"; else fail "MQTT -> Ditto: twin value is '${got:-?}', expected $value"; fi

wait "$sub_pid" || true
if [ ! -s "$event_file" ]; then
  fail "Ditto published no twin event on openegiz/#"
elif grep -qi '"authorization"' "$event_file"; then
  fail "twin events on MQTT leak the HTTP Authorization header"
else
  pass "twin event published on openegiz/# without credentials"
fi
rm -f "$event_file"

flux="from(bucket:\"default\") |> range(start:-5m) |> filter(fn:(r) => r.thingId == \"$THING\") |> last()"
wait_influx "$flux" ",$value," \
  "Ditto -> Telegraf -> InfluxDB (org openegiz) stored the value" \
  "value $value did not reach InfluxDB within 60 s"

echo "Grafana"
check "API healthy" curl_get "$GRAFANA/api/health"
check "OpenEgiz app plugin enabled" curl_grep '"enabled":true' -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA/api/plugins/ertis-opentwins-app/settings"
check "Unity panel plugin loaded" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA/api/plugins/ertis-unity-panel/settings"
check "InfluxDB datasource healthy" curl_grep '"OK"' -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA/api/datasources/uid/openegiz-influxdb/health"
# The OpenEgiz app reaches Ditto and the Extended API only through Grafana's
# plugin proxy, from inside the Grafana container.
PROXY="$GRAFANA/api/plugin-proxy/ertis-opentwins-app"
check_ditto "OpenEgiz app reaches Ditto (plugin proxy)" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/ditto/api/2/search/things?option=size(1)"
# The real Extended API resources, exactly the routes the app's Twins, Types
# and Policies pages call. A bare root check would pass even with the API
# half-broken (express answers 404 on /).
check_ditto "extended API twins via plugin proxy" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/twins"
check_ditto "extended API types via plugin proxy" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/types"
check_ditto "extended API policies via plugin proxy" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/policies"

echo "Extended API and 3D Scene"
if [ "$PROFILE" = "dev" ]; then
  check_ditto "extended API twins (direct port)" curl_get "http://$HOST:$EXTENDED_API_PORT/api/twins"
fi
check "3D Scene server serves build/" curl_get -o /dev/null "$UNITY_URL"

echo "Example Oven"
for oven_id in org.openegiz:oven-01 org.openegiz:oven-02; do
  if ! curl_get -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/things/$oven_id" >/dev/null 2>&1; then
    OVEN_CLEANUP+=("$oven_id")
  fi
done
check "create oven twins from examples/oven/twins.json" env \
  DITTO_URL="$DITTO" DITTO_PASSWORD="$DITTO_PASSWORD" DITTO_CA_CERT="$CA_CERT" TWINS_FILE="$ROOT/examples/oven/twins.json" \
  python3 "$ROOT/examples/mine/setup_twins.py"

oven_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if run_oven_generator; then
  pass "oven generator published telemetry round"
else
  fail "oven generator failed to publish telemetry"
fi

oven_flux="from(bucket:\"default\") |> range(start: $oven_start) |> filter(fn:(r) => r.thingId == \"org.openegiz:oven-01\" and r._field == \"value_voltage_v_properties_value\") |> count()"
wait_influx "$oven_flux" ',[1-9][0-9]*,value_voltage_v_properties_value,' \
  "oven telemetry reaches InfluxDB (org openegiz)" \
  "no fresh Example Oven telemetry in InfluxDB since $oven_start"

if "${COMPOSE[@]}" ps -a --format '{{.Service}}' 2>/dev/null | grep -qx mine-setup || \
   docker ps -a --format '{{.Names}}' | grep -q '^openegiz-mine-simulator-'; then
  echo "Example Mine"
  for twin in mine-01 excavator-01 truck-01 truck-02 crusher-01; do
    check_ditto "twin org.openegiz.mine:$twin exists" curl_get -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/things/org.openegiz.mine:$twin"
  done
  mine_flux='from(bucket:"default") |> range(start:-2m) |> filter(fn:(r) => r.thingId == "org.openegiz.mine:truck-01" and r._field == "value_route_position_properties_value") |> count()'
  wait_influx "$mine_flux" ',[1-9][0-9]*,value_route_position_properties_value,' \
    "simulator telemetry reaches InfluxDB" \
    "no Example Mine telemetry in InfluxDB for the last 2 minutes"
  # Same query the app's Twins page sends.
  check_ditto "Twins UI lists the Example Mine twins" curl_grep 'org.openegiz.mine:truck-01' -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/ditto/api/2/search/things?filter=ne(attributes/_isType,true)&fields=thingId&option=size(200)"
  check "dashboard provisioned" curl_get -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA/api/dashboards/uid/openegiz-example-mine"
fi

echo
if [ $FAILED = 0 ]; then echo "Smoke test passed."; else echo "Smoke test FAILED."; exit 1; fi
