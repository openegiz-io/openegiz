# Twins and Telemetry

This guide uses the [Example Oven](../examples/oven/) Twin IDs. Start the [Dev Profile](docker-compose.md#dev-profile), or replace the URLs and credentials with those for your deployment.

## Create a Twin

In Grafana, open **OpenEgiz → Twins → New twin** and choose Policy `default:basic_policy`. When using the Ditto HTTP API directly, the resource path uses the Ditto term `things`.

```bash
. deploy/compose/.env
curl --fail-with-body -u "ditto:$DITTO_PASSWORD" \
  -X PUT -H 'Content-Type: application/json' \
  --data '{"policyId":"default:basic_policy","attributes":{"name":"Oven 01"}}' \
  "http://localhost:$DITTO_PORT/api/2/things/org.openegiz:oven-01"
```

Use a Policy to control which subjects can read or write the Twin. A Twin Type is a reusable definition of the attributes and features shared by a class of Twins.

## Publish Telemetry

Send a [Ditto protocol](https://eclipse.dev/ditto/protocol-overview.html) command to an MQTT topic under `telemetry/#`, such as `telemetry/oven-01`. The message's `topic` field identifies the Twin and operation in Ditto.

```json
{
  "topic": "org.openegiz/oven-01/things/twin/commands/modify",
  "path": "/features",
  "value": {
    "temperature": { "properties": { "value": 182.5, "unit": "°C" } },
    "power_kw": { "properties": { "value": 3.2, "unit": "kW" } }
  }
}
```

Publish the JSON with your MQTT client or use `make generate-data` to create the Example Oven Twins and stream Telemetry. The `/features` operation replaces the whole features object, so include each feature that should remain. A single-property update changes Twin state but can yield a generic `value` field in InfluxDB. Publishing the complete features object preserves feature names in the history.

Connect to `localhost:1883` without authentication in the Dev Profile. For the Production Profile, use the broker credentials and the configured TCP or TLS listener. See the [Compose](docker-compose.md#production-profile) and [Helm](kubernetes.md#production-profile) instructions.

## Read current state and history

- Read the latest features in the OpenEgiz app or `GET /api/2/things/org.openegiz:oven-01/features` on the Ditto API.
- Subscribe to `openegiz/twin/events/org.openegiz/oven-01` for Twin Events.
- In Grafana, select the provisioned datasource with UID `openegiz-influxdb`. InfluxDB uses organization `openegiz`, bucket `default`, measurement `mqtt_consumer`, tag `thingId`, and fields such as `value_temperature_properties_value`. Allow for Telegraf's 10-second flush interval.

See the [Example Mine](../examples/mine/) for multiple Twins and a provisioned dashboard, or run `make smoke` to check the complete pipeline.
