#!/usr/bin/env bash
#
# End-to-end black-box smoke test against a running OpenEgiz Helm v3 release.
# Exercises the full platform contract:
#   - All pods Running & Ready under arbitrary release/namespace names
#   - MongoDB & Extended API services strictly ClusterIP
#   - Ditto health, default policy, Mosquitto connections, and JVM heap headroom
#   - MQTT authentication enforcement when allow_anonymous=false (Production Profile)
#   - Telemetry loop: MQTT -> Ditto -> Twin Event (no Authorization header) -> Telegraf -> InfluxDB (org openegiz)
#   - Grafana health, Plugin Bundle (ertis-opentwins-app + ertis-unity-panel),
#     InfluxDB datasource (openegiz-influxdb), and plugin proxy to Ditto & Extended API (/twins, /types, /policies)
#   - 3D Scene server PVC persistence across pod deletion/restart
#
# Usage:
#   RELEASE_NAME=openegiz NAMESPACE=openegiz bash scripts/helm-smoke.sh
#   RELEASE_NAME=e2e-rel NAMESPACE=e2e-ns SECRET_NAME=e2e-creds bash scripts/helm-smoke.sh
#
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-openegiz}"
NAMESPACE="${NAMESPACE:-openegiz}"
SECRET_NAME="${SECRET_NAME:-}"

PF_DITTO_PORT="${PF_DITTO_PORT:-18080}"
PF_GRAFANA_PORT="${PF_GRAFANA_PORT:-13000}"
PF_SCENE_PORT="${PF_SCENE_PORT:-18090}"

TWIN_ID="org.openegiz:helm-smoke-$$"
SCENE_FILE="helm-smoke-$$.txt"
SCENE_CONTENT="openegiz-pvc-persistence-$$"
FAILED=0
PF_PIDS=()

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILED=1; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

check_ditto() {
  local name="$1"; shift
  for _ in $(seq 1 20); do
    if "$@" >/dev/null 2>&1; then pass "$name"; return; fi
    sleep 3
  done
  fail "$name"
}

k() { kubectl -n "$NAMESPACE" "$@"; }

pod_for() {
  k get pods -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=$1" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

svc_for() {
  k get svc -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=$1" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

secret_key() {
  k get secret "$SECRET_NAME" -o "jsonpath={.data.$1}" | base64 -d
}

start_port_forward() {
  local svc="$1" local_port="$2" remote_port="$3"
  k port-forward "svc/$svc" "${local_port}:${remote_port}" >/dev/null 2>&1 &
  local pid=$!
  PF_PIDS+=("$pid")
  for _ in $(seq 1 30); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${local_port}/" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cleanup() {
  if [ -n "${DITTO_PASSWORD:-}" ]; then
    curl -s -o /dev/null -u "ditto:$DITTO_PASSWORD" -X DELETE "http://127.0.0.1:${PF_DITTO_PORT}/api/2/things/$TWIN_ID" || true
  fi
  local sp
  sp="$(pod_for scene-server)"
  if [ -n "$sp" ]; then
    k exec -c scene-server "$sp" -- rm -f "/usr/share/nginx/html/build/$SCENE_FILE" >/dev/null 2>&1 || true
  fi
  for pid in ${PF_PIDS[@]+"${PF_PIDS[@]}"}; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

echo "Kubernetes workloads (release=${RELEASE_NAME}, namespace=${NAMESPACE})"

# Discover Secret name automatically if not provided.
if [ -z "$SECRET_NAME" ]; then
  SECRET_NAME="$(k get deploy "$(svc_for ditto-nginx)" \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DITTO_PASSWORD")].valueFrom.secretKeyRef.name}' 2>/dev/null || true)"
fi
if [ -z "$SECRET_NAME" ]; then
  echo "ERROR: could not determine credentials Secret name for release=${RELEASE_NAME} in namespace=${NAMESPACE}" >&2
  exit 1
fi
pass "resolved credentials secret: $SECRET_NAME"

DITTO_PASSWORD="$(secret_key ditto-password)"
DITTO_DEVOPS_PASSWORD="$(secret_key ditto-devops-password)"
GRAFANA_ADMIN_PASSWORD="$(secret_key grafana-admin-password)"
INFLUXDB_TOKEN="$(secret_key influxdb-token)"

# Detect whether Mosquitto authentication is enabled in the deployed ConfigMap.
MOSQUITTO_CM="$(svc_for mosquitto)-config"
MQTT_AUTH_ENABLED="false"
if k get cm "$MOSQUITTO_CM" -o jsonpath='{.data.mosquitto\.conf}' 2>/dev/null | grep -q 'allow_anonymous false'; then
  MQTT_AUTH_ENABLED="true"
  MQTT_USERNAME="$(secret_key mqtt-username)"
  MQTT_PASSWORD="$(secret_key mqtt-password)"
fi

for comp in mongodb influxdb mosquitto telegraf ditto-policies ditto-things ditto-things-search ditto-connectivity ditto-gateway ditto-nginx extended-api grafana scene-server; do
  pod="$(pod_for "$comp")"
  if [ -z "$pod" ]; then
    fail "component $comp pod exists"
    continue
  fi
  ready="$(k get pod "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [ "$ready" = "True" ]; then
    pass "$comp pod ready ($pod)"
  else
    fail "$comp pod not ready ($pod: Ready=${ready:-?})"
  fi
done

# Verify MongoDB and Extended API remain strictly ClusterIP.
for internal_comp in mongodb extended-api; do
  svc="$(svc_for "$internal_comp")"
  svc_type="$(k get svc "$svc" -o jsonpath='{.spec.type}' 2>/dev/null || true)"
  if [ "$svc_type" = "ClusterIP" ]; then
    pass "$internal_comp service is strictly ClusterIP ($svc)"
  else
    fail "$internal_comp service type is '${svc_type:-?}', expected ClusterIP"
  fi
done

# Verify 3D Scene server PVC is Bound.
scene_pvc="$(k get pvc -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=scene-server" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
if [ "$scene_pvc" = "Bound" ]; then
  pass "scene-server PersistentVolumeClaim is Bound"
else
  fail "scene-server PersistentVolumeClaim phase is '${scene_pvc:-missing}', expected Bound"
fi

# Start port-forwards for black-box HTTP checks.
DITTO_SVC="$(svc_for ditto-nginx)"
GRAFANA_SVC="$(svc_for grafana)"
SCENE_SVC="$(svc_for scene-server)"

start_port_forward "$DITTO_SVC" "$PF_DITTO_PORT" 80 || { fail "port-forward to $DITTO_SVC"; exit 1; }
start_port_forward "$GRAFANA_SVC" "$PF_GRAFANA_PORT" 3000 || { fail "port-forward to $GRAFANA_SVC"; exit 1; }
start_port_forward "$SCENE_SVC" "$PF_SCENE_PORT" 80 || { fail "port-forward to $SCENE_SVC"; exit 1; }

DITTO="http://127.0.0.1:${PF_DITTO_PORT}"
GRAFANA="http://127.0.0.1:${PF_GRAFANA_PORT}"
SCENE="http://127.0.0.1:${PF_SCENE_PORT}"

echo "Ditto"
check_ditto "status/health is UP" sh -c "curl -sf -u devops:$DITTO_DEVOPS_PASSWORD $DITTO/status/health | grep -q '\"UP\"'"
check_ditto "default policy exists" curl -sf -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/policies/default:basic_policy"
for c in mosquitto-source-connection mosquitto-target-connection; do
  check_ditto "connection $c open" sh -c "curl -sf -u devops:$DITTO_DEVOPS_PASSWORD $DITTO/api/2/connections/$c/status | grep -q '\"open\"'"
done
check_ditto "create test twin" curl -sf -u "ditto:$DITTO_PASSWORD" -X PUT -H 'Content-Type: application/json' \
  -d '{"policyId":"default:basic_policy","features":{"smoke":{"properties":{"value":0}}}}' "$DITTO/api/2/things/$TWIN_ID"

echo "Ditto memory"
for comp in ditto-policies ditto-things ditto-things-search ditto-connectivity ditto-gateway; do
  pod="$(pod_for "$comp")"
  heap="" limit=""
  for _ in 1 2 3; do
    heap="$(k exec "$pod" -- curl -s -m 5 localhost:9095/ 2>/dev/null \
      | awk '/^jvm_memory_max_bytes\{region="heap"/ {printf "%d", $2 / 1048576}')" || true
    [ -n "$heap" ] && break
    sleep 3
  done
  limit="$(k exec "$pod" -- sh -c 'cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes' 2>/dev/null \
    | awk '/^[0-9]+$/ {printf "%d", $1 / 1048576}')" || true
  if [ -z "$heap" ] || [ -z "$limit" ]; then
    fail "$comp: could not read max heap (${heap:-?} MiB) or container limit (${limit:-?} MiB)"
  elif [ $((limit - heap)) -ge 512 ]; then
    pass "$comp: max heap ${heap} MiB leaves $((limit - heap)) MiB of its ${limit} MiB limit"
  else
    fail "$comp: max heap ${heap} MiB leaves $((limit - heap)) MiB of its ${limit} MiB limit (need 512)"
  fi
done

echo "Telemetry loop (MQTT auth=${MQTT_AUTH_ENABLED})"
MOSQUITTO_POD="$(pod_for mosquitto)"
INFLUXDB_POD="$(pod_for influxdb)"

MQTT_AUTH_ARGS=()
if [ "$MQTT_AUTH_ENABLED" = "true" ]; then
  if k exec -c mosquitto "$MOSQUITTO_POD" -- mosquitto_pub -h localhost -t telemetry/anon-check -m '{"test":1}' >/dev/null 2>&1; then
    fail "anonymous MQTT publish was accepted despite allow_anonymous false"
  else
    pass "anonymous MQTT publish rejected"
  fi
  MQTT_AUTH_ARGS=(-u "$MQTT_USERNAME" -P "$MQTT_PASSWORD")
fi

value=$((RANDOM % 1000 + 1))
msg=$(printf '{"topic":"%s/%s/things/twin/commands/modify","path":"/features/smoke/properties/value","value":%s}' \
  "${TWIN_ID%%:*}" "${TWIN_ID#*:}" "$value")

event_file="$(mktemp)"
k exec -c mosquitto "$MOSQUITTO_POD" -- mosquitto_sub -h localhost ${MQTT_AUTH_ARGS[@]+"${MQTT_AUTH_ARGS[@]}"} -C 1 -W 30 \
  -t "openegiz/twin/events/${TWIN_ID%%:*}/${TWIN_ID#*:}" >"$event_file" 2>/dev/null &
sub_pid=$!
sleep 2
k exec -c mosquitto "$MOSQUITTO_POD" -- mosquitto_pub -h localhost ${MQTT_AUTH_ARGS[@]+"${MQTT_AUTH_ARGS[@]}"} -t telemetry/smoke -m "$msg"

ok=0
for _ in $(seq 1 15); do
  got="$(curl -sf -u "ditto:$DITTO_PASSWORD" "$DITTO/api/2/things/$TWIN_ID/features/smoke/properties/value" || true)"
  if [ "$got" = "$value" ]; then ok=1; break; fi
  sleep 1
done
if [ "$ok" = 1 ]; then pass "MQTT -> Ditto updated the twin"; else fail "MQTT -> Ditto: twin value is '${got:-?}', expected $value"; fi

wait "$sub_pid" || true
if [ ! -s "$event_file" ]; then
  fail "Ditto published no twin event on openegiz/#"
elif grep -qi '"authorization"' "$event_file"; then
  fail "twin events on MQTT leak the HTTP Authorization header"
else
  pass "twin event published on openegiz/# without credentials"
fi
rm -f "$event_file"

flux="from(bucket:\"default\") |> range(start:-5m) |> filter(fn:(r) => r.thingId == \"$TWIN_ID\") |> last()"
influx_ok=0
for _ in $(seq 1 30); do
  if k exec "$INFLUXDB_POD" -- influx query --org openegiz --token "$INFLUXDB_TOKEN" --raw "$flux" 2>/dev/null \
      | grep -qE ",$value,"; then
    influx_ok=1
    break
  fi
  sleep 2
done
if [ "$influx_ok" = 1 ]; then
  pass "Ditto -> Telegraf -> InfluxDB (org openegiz) stored the value"
else
  fail "value $value did not reach InfluxDB within 60 s"
fi

echo "Grafana & Extended API"
check "API healthy" curl -sf --max-time 15 "$GRAFANA/api/health"
check "OpenEgiz app plugin enabled" sh -c "curl -sf --max-time 15 -u admin:$GRAFANA_ADMIN_PASSWORD $GRAFANA/api/plugins/ertis-opentwins-app/settings | grep -q '\"enabled\":true'"
check "Unity panel plugin loaded" curl -sf --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$GRAFANA/api/plugins/ertis-unity-panel/settings"
check "InfluxDB datasource healthy" sh -c "curl -sf --max-time 15 -u admin:$GRAFANA_ADMIN_PASSWORD $GRAFANA/api/datasources/uid/openegiz-influxdb/health | grep -q '\"OK\"'"

PROXY="$GRAFANA/api/plugin-proxy/ertis-opentwins-app"
check_ditto "OpenEgiz app reaches Ditto (plugin proxy)" curl -sf --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/ditto/api/2/search/things?option=size(1)"
check_ditto "extended API twins via plugin proxy" curl -sf --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/twins"
check_ditto "extended API types via plugin proxy" curl -sf --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/types"
check_ditto "extended API policies via plugin proxy" curl -sf --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$PROXY/extended/api/policies"

echo "3D Scene server PVC persistence"
check "scene-server serves /build/README.md" curl -sf -o /dev/null "$SCENE/build/README.md"

SCENE_POD="$(pod_for scene-server)"
tmp_scene="$(mktemp)"
printf '%s' "$SCENE_CONTENT" > "$tmp_scene"
chmod 0644 "$tmp_scene"
k cp -c scene-server "$tmp_scene" "${SCENE_POD}:/usr/share/nginx/html/build/${SCENE_FILE}"
rm -f "$tmp_scene"

got_before="$(curl -sf "$SCENE/build/${SCENE_FILE}" || true)"
if [ "$got_before" = "$SCENE_CONTENT" ]; then
  pass "uploaded 3D Scene artifact served before restart"
else
  fail "uploaded 3D Scene artifact mismatch before restart (got '${got_before:-?}')"
fi

# Delete the scene-server pod and confirm the PVC retains the uploaded file.
old_uid="$(k get pod "$SCENE_POD" -o jsonpath='{.metadata.uid}')"
k delete pod "$SCENE_POD" --wait=true >/dev/null
for _ in $(seq 1 60); do
  new_uid="$(k get pod "$SCENE_POD" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  new_ready="$(k get pod "$SCENE_POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [ -n "$new_uid" ] && [ "$new_uid" != "$old_uid" ] && [ "$new_ready" = "True" ]; then
    break
  fi
  sleep 2
done

# Re-open port-forward after pod recreation.
PF_SCENE_PORT_AFTER=$((PF_SCENE_PORT + 1))
start_port_forward "$SCENE_SVC" "$PF_SCENE_PORT_AFTER" 80 || fail "re-open port-forward to $SCENE_SVC after restart"
got_after="$(curl -sf "http://127.0.0.1:${PF_SCENE_PORT_AFTER}/build/${SCENE_FILE}" || true)"
if [ "$got_after" = "$SCENE_CONTENT" ]; then
  pass "3D Scene artifact persisted on PVC across pod restart"
else
  fail "3D Scene artifact lost after pod restart (got '${got_after:-?}')"
fi

echo
if [ "$FAILED" = 0 ]; then echo "Helm smoke test passed."; else echo "Helm smoke test FAILED."; exit 1; fi
