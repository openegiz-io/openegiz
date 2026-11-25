#!/bin/sh
# Production Profile entrypoint for Eclipse Mosquitto:
# - Generates a hashed password file from MQTT_USERNAME / MQTT_PASSWORD.
# - Optionally enables an MQTTS (TLS) listener on port 8883 when MQTTS_ENABLED=true.
set -eu

if [ -z "${MQTT_USERNAME:-}" ] || [ -z "${MQTT_PASSWORD:-}" ]; then
  echo "ERROR: MQTT_USERNAME and MQTT_PASSWORD must be set in the Production Profile." >&2
  exit 1
fi

PASSWD_FILE="/tmp/mosquitto.passwd"
CONF_FILE="/tmp/mosquitto.conf"

umask 077
mosquitto_passwd -b -c "$PASSWD_FILE" "$MQTT_USERNAME" "$MQTT_PASSWORD"
chown mosquitto:mosquitto "$PASSWD_FILE" 2>/dev/null || true
chmod 600 "$PASSWD_FILE"

cp /mosquitto/config/mosquitto.prod.conf "$CONF_FILE"

if [ "${MQTTS_ENABLED:-false}" = "true" ]; then
  CA_FILE="${MQTTS_CAFILE:-/mosquitto/certs/ca.crt}"
  CERT_FILE="${MQTTS_CERTFILE:-/mosquitto/certs/server.crt}"
  KEY_FILE="${MQTTS_KEYFILE:-/mosquitto/certs/server.key}"
  for f in "$CA_FILE" "$CERT_FILE" "$KEY_FILE"; do
    if [ ! -r "$f" ]; then
      echo "ERROR: MQTTS_ENABLED=true but TLS file is missing or unreadable: $f" >&2
      exit 1
    fi
  done
  cat >>"$CONF_FILE" <<EOF

listener 8883 0.0.0.0
cafile $CA_FILE
certfile $CERT_FILE
keyfile $KEY_FILE
tls_version tlsv1.2
EOF
fi

if [ "$(id -u)" = "0" ]; then
  [ -d "/mosquitto/data" ] && chown -R mosquitto:mosquitto /mosquitto/data || true
fi

exec /usr/sbin/mosquitto -c "$CONF_FILE"
