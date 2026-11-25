#!/usr/bin/env python3
"""Static contract checks for OpenEgiz Docker Compose Deployment Profiles.

Validates via `docker compose ... config --format json`:
  1. Dev Profile (`docker-compose.yml`): localhost quickstart, no Caddy, MongoDB internal-only.
  2. Production Profile (`docker-compose.yml` + `docker-compose.prod.yml`):
     - Caddy is the single HTTP/HTTPS entrypoint (ports 80 and 443).
     - MongoDB, InfluxDB, Extended API, Grafana, Ditto nginx, and Unity publish zero host ports.
     - Mosquitto publishes MQTT (1883) with auth enabled and authenticated healthcheck.
     - Telegraf and init receive MQTT credentials; Grafana is configured for HTTPS reverse proxy.
  3. Production Profile + MQTTS overlay (`docker-compose.mqtts.yml`):
     - Mosquitto enables MQTTS, mounts `/mosquitto/certs`, and publishes port 8883.
     - Internal-only services still publish zero host ports.
  4. Production Profile + Example Mine overlay (`examples/mine/compose.yml`):
     - Valid merged config and `mine-simulator` receives MQTT credentials.
"""

import json
import os
import subprocess
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE_DIR = os.path.join(ROOT, "deploy", "compose")
BASE_FILE = os.path.join(COMPOSE_DIR, "docker-compose.yml")
PROD_FILE = os.path.join(COMPOSE_DIR, "docker-compose.prod.yml")
MQTTS_FILE = os.path.join(COMPOSE_DIR, "docker-compose.mqtts.yml")
MINE_FILE = os.path.join(ROOT, "examples", "mine", "compose.yml")

TEST_ENV = {
    "OPENEGIZ_BIND": "127.0.0.1",
    "OPENEGIZ_PUBLIC_HOST": "localhost",
    "OPENEGIZ_DOMAIN": "twins.example.test",
    "OPENEGIZ_PROD_BIND": "0.0.0.0",
    "CADDY_TLS": "internal",
    "HTTP_PORT": "80",
    "HTTPS_PORT": "443",
    "GRAFANA_PORT": "3000",
    "DITTO_PORT": "8080",
    "EXTENDED_API_PORT": "8085",
    "UNITY_PORT": "8090",
    "INFLUXDB_PORT": "8086",
    "MQTT_PORT": "1883",
    "MQTTS_PORT": "8883",
    "MQTTS_ENABLED": "false",
    "GRAFANA_ADMIN_PASSWORD": "test-grafana-password",
    "DITTO_PASSWORD": "test-ditto-password",
    "DITTO_DEVOPS_PASSWORD": "test-devops-password",
    "DITTO_BASIC_AUTH": "ZGl0dG86dGVzdC1kaXR0by1wYXNzd29yZA==",
    "DITTO_DEVOPS_BASIC_AUTH": "ZGV2b3BzOnRlc3QtZGV2b3BzLXBhc3N3b3Jk",
    "INFLUXDB_ADMIN_PASSWORD": "test-influx-password",
    "INFLUXDB_TOKEN": "test-influx-token-012345678901234567890123",
    "MQTT_USERNAME": "openegiz",
    "MQTT_PASSWORD": "test-mqtt-password",
}

PROD_INTERNAL_ONLY_SERVICES = (
    "mongodb",
    "influxdb",
    "extended-api",
    "grafana",
    "ditto-nginx",
    "unity",
)


def compose_config(files: list[str], extra_env: dict[str, str] | None = None) -> dict:
    cmd = ["docker", "compose"]
    for path in files:
        if not os.path.isfile(path):
            raise AssertionError(f"missing compose file: {os.path.relpath(path, ROOT)}")
        cmd.extend(["-f", path])
    cmd.extend(["config", "--format", "json"])

    env = os.environ.copy()
    env.update(TEST_ENV)
    if extra_env:
        env.update(extra_env)

    proc = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(
            f"`{' '.join(cmd)}` failed (exit {proc.returncode}):\n{proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def published_targets(service: dict) -> set[int]:
    ports = service.get("ports") or []
    return {int(p["target"]) for p in ports}


def service_env(service: dict) -> dict[str, str]:
    raw = service.get("environment") or {}
    if isinstance(raw, dict):
        return {k: "" if v is None else str(v) for k, v in raw.items()}
    result: dict[str, str] = {}
    for item in raw:
        if "=" in item:
            k, v = item.split("=", 1)
            result[k] = v
    return result


def check_dev_profile() -> None:
    cfg = compose_config([BASE_FILE])
    services = cfg["services"]

    assert "caddy" not in services, "Dev Profile must not include caddy"
    assert not services["mongodb"].get("ports"), "Dev Profile mongodb must not publish host ports"

    for name, expected_port in (
        ("grafana", 3000),
        ("ditto-nginx", 80),
        ("extended-api", 8080),
        ("influxdb", 8086),
        ("mosquitto", 1883),
        ("unity", 80),
    ):
        ports = services[name].get("ports") or []
        assert any(
            int(p["target"]) == expected_port and p.get("host_ip") == "127.0.0.1"
            for p in ports
        ), f"Dev Profile {name} must bind port {expected_port} on 127.0.0.1, got: {ports}"

    telegraf_env = service_env(services["telegraf"])
    assert telegraf_env.get("MQTT_USERNAME", "") == "", "Dev Profile telegraf must use anonymous MQTT"
    assert telegraf_env.get("MQTT_PASSWORD", "") == "", "Dev Profile telegraf must use anonymous MQTT"


def check_prod_profile() -> None:
    cfg = compose_config([BASE_FILE, PROD_FILE])
    services = cfg["services"]

    assert "caddy" in services, "Production Profile must define caddy service"
    caddy_targets = published_targets(services["caddy"])
    assert caddy_targets == {80, 443}, f"Production Profile caddy must publish 80 & 443, got: {caddy_targets}"

    for name in PROD_INTERNAL_ONLY_SERVICES:
        ports = services[name].get("ports") or []
        assert not ports, f"Production Profile {name} must not publish host ports, got: {ports}"

    mosquitto = services["mosquitto"]
    assert published_targets(mosquitto) == {1883}, (
        f"Production Profile mosquitto without MQTTS must publish only 1883, got: {published_targets(mosquitto)}"
    )
    mosq_env = service_env(mosquitto)
    assert mosq_env.get("MQTT_USERNAME") == "openegiz", "mosquitto must receive MQTT_USERNAME"
    assert mosq_env.get("MQTT_PASSWORD") == "test-mqtt-password", "mosquitto must receive MQTT_PASSWORD"
    hc = " ".join(mosquitto.get("healthcheck", {}).get("test") or [])
    assert "-u" in hc and "-P" in hc, f"Production Profile mosquitto healthcheck must authenticate, got: {hc}"

    for name in ("telegraf", "init"):
        env = service_env(services[name])
        assert env.get("MQTT_USERNAME") == "openegiz", f"Production Profile {name} must receive MQTT_USERNAME"
        assert env.get("MQTT_PASSWORD") == "test-mqtt-password", f"Production Profile {name} must receive MQTT_PASSWORD"
    assert service_env(services["init"]).get("MQTT_AUTH_ENABLED") == "true", (
        "Production Profile init must set MQTT_AUTH_ENABLED=true"
    )

    grafana_env = service_env(services["grafana"])
    assert grafana_env.get("GF_SERVER_DOMAIN") == "twins.example.test", "Grafana must set GF_SERVER_DOMAIN"
    assert grafana_env.get("GF_SERVER_ROOT_URL", "").startswith("https://"), (
        f"Grafana GF_SERVER_ROOT_URL must use https://, got: {grafana_env.get('GF_SERVER_ROOT_URL')}"
    )
    assert grafana_env.get("GF_SECURITY_COOKIE_SECURE") == "true", (
        "Production Profile Grafana must set GF_SECURITY_COOKIE_SECURE=true"
    )


def check_prod_mqtts_overlay() -> None:
    cfg = compose_config([BASE_FILE, PROD_FILE, MQTTS_FILE], {"MQTTS_ENABLED": "true"})
    services = cfg["services"]

    for name in PROD_INTERNAL_ONLY_SERVICES:
        ports = services[name].get("ports") or []
        assert not ports, f"Production+MQTTS {name} must not publish host ports, got: {ports}"

    mosquitto = services["mosquitto"]
    assert published_targets(mosquitto) == {1883, 8883}, (
        f"Production+MQTTS mosquitto must publish 1883 and 8883, got: {published_targets(mosquitto)}"
    )
    assert service_env(mosquitto).get("MQTTS_ENABLED") == "true", "MQTTS overlay must set MQTTS_ENABLED=true"
    targets = {v.get("target") for v in (mosquitto.get("volumes") or []) if isinstance(v, dict)}
    assert "/mosquitto/certs" in targets, f"MQTTS overlay must mount /mosquitto/certs, got: {targets}"


def check_prod_with_example_mine() -> None:
    cfg = compose_config([BASE_FILE, PROD_FILE, MINE_FILE])
    sim_env = service_env(cfg["services"]["mine-simulator"])
    assert sim_env.get("MQTT_USERNAME") == "openegiz", "mine-simulator must receive MQTT_USERNAME in prod"
    assert sim_env.get("MQTT_PASSWORD") == "test-mqtt-password", "mine-simulator must receive MQTT_PASSWORD in prod"


def main() -> int:
    checks = [
        ("dev profile", check_dev_profile),
        ("production profile", check_prod_profile),
        ("production + mqtts overlay", check_prod_mqtts_overlay),
        ("production + example-mine overlay", check_prod_with_example_mine),
    ]
    failed = 0
    for label, fn in checks:
        try:
            fn()
            print(f"ok   compose profile check: {label}")
        except AssertionError as exc:
            print(f"FAIL compose profile check: {label}: {exc}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
