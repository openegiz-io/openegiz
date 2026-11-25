#!/usr/bin/env bash
# Black-box checks shared by Compose and Helm smoke. The caller provides
# curl_get and mqtt_client for the running deployment.

ditto_http() { curl_get --max-time 15 -u "ditto:$DITTO_PASSWORD" "$@"; }
grafana_http() { curl_get --max-time 15 -u "admin:$GRAFANA_ADMIN_PASSWORD" "$@"; }

observe_twin_event() (
  local twin_id="$1" path="$2" value_json="$3" topic event_file sub_pid
  shift 3
  topic="openegiz/twin/events/${twin_id%%:*}/${twin_id#*:}"
  event_file="$(mktemp)" || exit 1
  # The retained version message confirms that the same client is subscribed
  # before we perform the update. MQTT v5 also exposes any user properties.
  mqtt_client mosquitto_sub -V mqttv5 -q 1 -F '%j' -C 2 -W 30 \
    -t "$topic" -t '$SYS/broker/version' >"$event_file" 2>/dev/null &
  sub_pid=$!
  trap 'kill "$sub_pid" 2>/dev/null || true; wait "$sub_pid" 2>/dev/null || true; rm -f "$event_file"' EXIT
  for _ in $(seq 1 40); do
    [ -s "$event_file" ] && break
    sleep 0.25
  done
  [ -s "$event_file" ] || exit 1
  "$@" >/dev/null 2>&1 || exit 1
  wait "$sub_pid" || exit 1

  # Keep the capture private, including on failure.
  python3 - "$event_file" "$topic" "$path" "$value_json" <<'PY'
import json
import sys

filename, topic, path, value_json = sys.argv[1:]
expected = json.loads(value_json)
with open(filename, encoding="utf-8") as capture:
    for line in capture:
        packet = json.loads(line)
        if packet["topic"] != topic:
            continue
        event = json.loads(packet["payload"])
        if event.get("path") == path and event.get("value") == expected:
            headers = event.get("headers", {})
            properties = packet.get("properties", {}).get("user-properties", {})
            sys.exit(any(key.lower() == "authorization" for key in (*headers, *properties)))
sys.exit(1)
PY
)

check_smoke_twin_events() {
  local twin_id="$1" value="$2" msg got=""
  local thing_url="$DITTO/api/2/things/$1" path="/features/smoke/properties/value"
  msg=$(printf '{"topic":"%s/%s/things/twin/commands/modify","path":"%s","value":%s}' \
    "${twin_id%%:*}" "${twin_id#*:}" "$path" "$value")
  check "MQTT update produces a matching Twin Event on openegiz/#" \
    observe_twin_event "$twin_id" "$path" "$value" mqtt_client mosquitto_pub -t telemetry/smoke -m "$msg"

  for _ in $(seq 1 15); do
    got="$(ditto_http "$thing_url$path" || true)"
    [ "$got" = "$value" ] && break
    sleep 1
  done
  if [ "$got" = "$value" ]; then
    pass "MQTT -> Ditto updated the twin"
  else
    fail "MQTT -> Ditto did not store the expected twin value"
  fi

  # An object gives Telegraf a separate field. A scalar string would use the
  # same InfluxDB field as numeric MQTT Telemetry and cause type conflicts.
  local marker_path="/attributes/smokeHttp" marker='{"authorizationCheck":"http-update"}'
  check "Authenticated HTTP update produces a matching Twin Event without Authorization" \
    observe_twin_event "$twin_id" "$marker_path" "$marker" ditto_http \
    -X PUT -H 'Content-Type: application/json' -d "$marker" "$thing_url$marker_path"
}

grafana_telemetry_point() {
  local query
  query="$(python3 - "$1" <<'PY'
import json
import sys

flux = (
    'from(bucket: "default") |> range(start: v.timeRangeStart, stop: v.timeRangeStop) '
    f'|> filter(fn: (r) => r.thingId == "{sys.argv[1]}" and r._field == "value") '
    '|> keep(columns: ["_time", "_value"])'
)
print(json.dumps({
    "from": "now-1h",
    "to": "now",
    "queries": [{
        "refId": "A",
        "datasource": {"uid": "openegiz-influxdb", "type": "influxdb"},
        "query": flux,
    }],
}))
PY
)" || return 1
  grafana_http -H 'Content-Type: application/json' -d "$query" "$GRAFANA/api/ds/query" |
    python3 -c '
import json
import sys

expected = int(sys.argv[1])
result = json.load(sys.stdin)["results"]["A"]
if result.get("status") != 200:
    sys.exit(1)
for frame in result.get("frames", []):
    fields = frame["schema"].get("fields", [])
    data = frame["data"]
    columns = {field["type"]: index for index, field in enumerate(fields)}
    if "time" not in columns or "number" not in columns:
        continue
    time_col = columns["time"]
    timestamps = data["values"][time_col]
    values = data["values"][columns["number"]]
    nanos = data.get("nanos", [None] * len(fields))[time_col] or [0] * len(timestamps)
    for timestamp, ns, value in zip(timestamps, nanos, values):
        if value == expected and timestamp is not None:
            print(f"{timestamp}:{ns}")
            sys.exit(0)
sys.exit(1)
' "$2"
}

twin_type_has_name() {
  grafana_http "$1" | python3 -c '
import json
import sys

twin_type = json.load(sys.stdin)
sys.exit(not (twin_type["thingId"] == sys.argv[1] and twin_type["attributes"]["name"] == sys.argv[2]))
' "$2" "$3"
}

manage_twin_type() (
  local type_id="$1" url="$PROXY/extended/api/types/$1" status
  # A known ID makes cleanup possible even when a write times out.
  trap 'grafana_http -X DELETE "$url" >/dev/null 2>&1 ||
    ditto_http -X DELETE "$DITTO/api/2/things/$type_id" >/dev/null 2>&1 || true' EXIT
  grafana_http -X PUT -H 'Content-Type: application/json' \
    -d '{"policyId":"default:basic_policy","attributes":{"name":"Smoke Type"}}' "$url" >/dev/null || exit 1
  twin_type_has_name "$url" "$type_id" "Smoke Type" || exit 1
  grafana_http -X PATCH -H 'Content-Type: application/json' \
    -d '{"attributes":{"name":"Updated Smoke Type"}}' "$url" >/dev/null || exit 1
  twin_type_has_name "$url" "$type_id" "Updated Smoke Type" || exit 1
  grafana_http -X DELETE "$url" >/dev/null || exit 1
  status="$(grafana_http -o /dev/null -w '%{http_code}' "$url" || true)"
  [ "$status" = 404 ] || exit 1
  trap - EXIT
)
