#!/bin/sh
# One-shot equivalent of the Helm post-install jobs: default policy plus the
# Ditto <-> Mosquitto connections. Idempotent: PUT creates or replaces, so a
# re-run after `make up` on an existing stack is harmless.
set -eu

DITTO_URL="http://ditto-nginx:80"
DEVOPS_AUTH="devops:${DITTO_DEVOPS_PASSWORD}"
DITTO_AUTH="ditto:${DITTO_PASSWORD}"

put() {
    # $1 auth, $2 url, $3 body file
    # Every PUT here is idempotent, so a timeout, a 5xx or no answer is
    # retried, a bounded number of times: a ready Ditto can still time out on
    # a write while its JVMs warm up on a busy host, answering 503 "ask.error
    # ... Please retry" or 408 "command.timeout". Other 4xx fail at once.
    attempt=1
    while :; do
        status=$(curl --silent --show-error --max-time 70 --output /tmp/response --write-out '%{http_code}' \
            -X PUT -u "$1" -H 'Content-Type: application/json' --data-binary "@$3" "$2") || true
        case "$status" in
            2??) echo "ok   $status PUT $2"; return 0 ;;
            000|408|5??)
                if [ "$attempt" -lt 10 ]; then
                    echo "retry $status PUT $2 (attempt $attempt of 10): $(cat /tmp/response 2>/dev/null)"
                    attempt=$((attempt + 1))
                    sleep 5
                    continue
                fi ;;
        esac
        echo "FAIL $status PUT $2"; cat /tmp/response; echo; exit 1
    done
}

# "UP" from the gateway only means every role has a reachable node. Also wait
# until every node reports ready on its Akka management port: an Up cluster
# member whose shard regions are registered, so it can serve writes.
ditto_ready() {
    curl --silent --fail --max-time 10 -u "$DEVOPS_AUTH" "$DITTO_URL/status/health" \
        | grep -q '"status" *: *"UP"' || return 1
    for node in policies things things-search connectivity gateway; do
        curl --silent --fail --max-time 10 -o /dev/null "http://$node:7626/ready" || return 1
    done
}

echo "Waiting for Ditto to be ready..."
i=0
until ditto_ready; do
    i=$((i + 1))
    if [ "$i" -ge 90 ]; then
        echo "Ditto did not become ready within 7.5 minutes" >&2
        exit 1
    fi
    sleep 5
done
echo "Ditto is ready"

urlencode() {
    # Percent-encode every byte outside RFC 3986 unreserved [A-Za-z0-9._~-],
    # making the output safe for URI userinfo, JSON strings, and sed.
    printf '%s' "$1" | od -An -tx1 -v | tr -s ' \n' '\n' | while IFS= read -r hex; do
        [ -n "$hex" ] || continue
        case "$hex" in
            2d|2e|3[0-9]|4[1-9a-f]|5[0-9a]|5f|6[1-9a-f]|7[0-9a]|7e)
                printf "\\$(printf '%03o' "0x$hex")" ;;
            *)
                printf '%%%s' "$(printf '%s' "$hex" | tr 'a-f' 'A-F')" ;;
        esac
    done
}

put_connection() {
    # $1 url, $2 template json
    if [ "${MQTT_AUTH_ENABLED:-false}" = "true" ]; then
        if [ -z "${MQTT_USERNAME:-}" ] || [ -z "${MQTT_PASSWORD:-}" ]; then
            echo "ERROR: MQTT_AUTH_ENABLED=true requires MQTT_USERNAME and MQTT_PASSWORD" >&2
            exit 1
        fi
        conn_file="/tmp/connection.json"
        umask 077
        enc_user=$(urlencode "$MQTT_USERNAME")
        enc_pass=$(urlencode "$MQTT_PASSWORD")
        sed "s|tcp://mosquitto:1883|tcp://${enc_user}:${enc_pass}@mosquitto:1883|g" "$2" >"$conn_file"
        put "$DEVOPS_AUTH" "$1" "$conn_file"
        rm -f "$conn_file"
    else
        put "$DEVOPS_AUTH" "$1" "$2"
    fi
}

put "$DITTO_AUTH"  "$DITTO_URL/api/2/policies/default:basic_policy"                  /init/basic-policy.json
put_connection     "$DITTO_URL/api/2/connections/mosquitto-source-connection"        /init/mosquitto-source-connection.json
put_connection     "$DITTO_URL/api/2/connections/mosquitto-target-connection"        /init/mosquitto-target-connection.json
echo "OpenEgiz initialised"
