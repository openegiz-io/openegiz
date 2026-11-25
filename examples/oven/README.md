# Example Oven

Minimal Reference Example streaming electrical Telemetry for two industrial oven Twins (`org.openegiz:oven-01`, `org.openegiz:oven-02`) into OpenEgiz over MQTT (Mosquitto).

## Features

| Feature | Description | Typical range |
|---|---|---|
| `voltage_v` | Supply voltage (V) | 200–240 |
| `current_a` | Heating current (A) | 5–50 |
| `active_power_kw` | Active power (kW) | 1–10 |
| `power_factor` | Power factor (cosφ) | 0.75–0.99 |

## Run it

Start the platform with `make up` and run the example from the repository root.

```bash
make generate-data
```

On first run this creates `examples/.venv`, creates or updates the oven Twins in Ditto from [`twins.json`](twins.json), and publishes Telemetry every 5 seconds. Stop with `Ctrl+C`.

Ports and credentials are loaded from `deploy/compose/.env`. For Kubernetes, forward the Ditto and MQTT ports and pass them explicitly. For an authenticated broker, also pass `MQTT_USERNAME` and `MQTT_PASSWORD`.

```bash
make generate-data MQTT_PORT=11883 DITTO_URL=http://localhost:18080 DITTO_PASSWORD=...
```

To publish from the Python environment directly, run the generator with the broker settings.

```bash
examples/.venv/bin/python examples/oven/data_generator.py --mqtt-port 1883 --interval 2
```

## Verify Telemetry

```bash
set -a; . deploy/compose/.env; set +a
curl -fsS -u "ditto:$DITTO_PASSWORD" "http://localhost:$DITTO_PORT/api/2/things/org.openegiz:oven-01/features" | python3 -m json.tool
```
