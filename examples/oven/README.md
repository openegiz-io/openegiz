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

From the repository root, with the platform running (`make up`):

```bash
make generate-data
```

On first run this creates `examples/.venv`, creates or updates the oven Twins in Ditto from [`twins.json`](twins.json), and publishes Telemetry every 5 seconds. Stop with `Ctrl+C`.

Ports and Ditto credentials are loaded from `deploy/compose/.env`. To target another deployment (such as Kubernetes), pass them explicitly:

```bash
make generate-data MQTT_PORT=30511 DITTO_URL=http://localhost:30525 DITTO_PASSWORD=...
```

You can also run the generator directly:

```bash
examples/.venv/bin/python examples/oven/data_generator.py --mqtt-port 1883 --interval 2
```

## Verify Telemetry

```bash
set -a; . deploy/compose/.env; set +a
curl -s -u "ditto:$DITTO_PASSWORD" http://localhost:8080/api/2/things/org.openegiz:oven-01/features | python3 -m json.tool
```
