# Reference Examples

Two self-contained industrial Reference Examples ship with OpenEgiz to demonstrate and verify end-to-end Telemetry ingestion, Twin state management, time-series history, and Grafana dashboards:

| Example | What it demonstrates | Command |
|---|---|---|
| [mine/](mine/) | **Example Mine**: open-pit haul cycle (excavator, two haul trucks, crusher) with Twins, containerized simulator, and Grafana dashboard | `make example-mine` |
| [oven/](oven/) | **Example Oven**: minimal two-oven electrical Telemetry publisher over MQTT | `make generate-data` |

The Python examples share one dependency list, [`requirements.txt`](requirements.txt):

```bash
python3 -m venv examples/.venv
examples/.venv/bin/pip install -r examples/requirements.txt
```

By default, both examples target the Docker Compose stack (`MQTT_PORT=1883`, `DITTO_URL=http://localhost:8080`, credentials from `deploy/compose/.env`).
