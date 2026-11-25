#!/usr/bin/env python3
"""Unit tests for compose-env.sh and Reference Example MQTT auth / TLS CLI seams."""

import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE_ENV_SH = os.path.join(ROOT, "scripts", "compose-env.sh")
MINE_SIM = os.path.join(ROOT, "examples", "mine", "simulator.py")
OVEN_GEN = os.path.join(ROOT, "examples", "oven", "data_generator.py")
SETUP_TWINS = os.path.join(ROOT, "examples", "mine", "setup_twins.py")


def parse_env(path: str) -> dict[str, str]:
    data: dict[str, str] = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            data[k] = v
    return data


class TestComposeEnv(unittest.TestCase):
    def test_fresh_env_contains_dev_and_prod_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = os.path.join(tmp, ".env")
            proc = subprocess.run(
                ["bash", COMPOSE_ENV_SH, env_path],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            values = parse_env(env_path)
            for key in (
                "OPENEGIZ_BIND",
                "OPENEGIZ_PUBLIC_HOST",
                "GRAFANA_ADMIN_PASSWORD",
                "DITTO_PASSWORD",
                "DITTO_DEVOPS_PASSWORD",
                "INFLUXDB_TOKEN",
                "MQTT_USERNAME",
                "MQTT_PASSWORD",
                "OPENEGIZ_DOMAIN",
                "OPENEGIZ_PROD_BIND",
                "CADDY_TLS",
                "HTTP_PORT",
                "HTTPS_PORT",
                "MQTTS_ENABLED",
                "MQTTS_PORT",
            ):
                self.assertIn(key, values, f"missing key {key} in generated .env")
            self.assertEqual(values["MQTT_USERNAME"], "openegiz")
            self.assertGreaterEqual(len(values["MQTT_PASSWORD"]), 24)
            self.assertEqual(values["OPENEGIZ_DOMAIN"], "localhost")
            self.assertEqual(values["CADDY_TLS"], "internal")
            self.assertEqual(values["MQTTS_ENABLED"], "false")

    def test_existing_env_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = os.path.join(tmp, ".env")
            subprocess.run(["bash", COMPOSE_ENV_SH, env_path], check=True)
            before = parse_env(env_path)
            subprocess.run(["bash", COMPOSE_ENV_SH, env_path], check=True)
            after = parse_env(env_path)
            self.assertEqual(before, after)

    def test_legacy_env_is_upgraded_without_changing_existing_passwords(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_path = os.path.join(tmp, ".env")
            with open(env_path, "w", encoding="utf-8") as fh:
                fh.write(
                    "OPENEGIZ_BIND=127.0.0.1\n"
                    "DITTO_PASSWORD=existing-secret-123\n"
                    "GRAFANA_ADMIN_PASSWORD=existing-grafana-456\n"
                )
            proc = subprocess.run(
                ["bash", COMPOSE_ENV_SH, env_path],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            values = parse_env(env_path)
            self.assertEqual(values["DITTO_PASSWORD"], "existing-secret-123")
            self.assertEqual(values["GRAFANA_ADMIN_PASSWORD"], "existing-grafana-456")
            self.assertEqual(values["MQTT_USERNAME"], "openegiz")
            self.assertGreaterEqual(len(values["MQTT_PASSWORD"]), 24)
            self.assertEqual(values["OPENEGIZ_DOMAIN"], "localhost")
            self.assertEqual(values["CADDY_TLS"], "internal")


class TestReferenceExampleCLIs(unittest.TestCase):
    def test_mine_simulator_accepts_mqtt_auth_and_tls_flags(self) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                MINE_SIM,
                "--dry-run",
                "--steps",
                "1",
                "--mqtt-username",
                "openegiz",
                "--mqtt-password",
                "secret",
                "--mqtt-tls",
                "--mqtt-ca-certs",
                "/tmp/ca.crt",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("org.openegiz.mine/truck-01", proc.stdout)

    def test_oven_generator_help_documents_mqtt_auth_and_tls_flags(self) -> None:
        proc = subprocess.run(
            [sys.executable, OVEN_GEN, "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for flag in ("--mqtt-username", "--mqtt-password", "--mqtt-tls", "--mqtt-ca-certs"):
            self.assertIn(flag, proc.stdout)

    def test_setup_twins_supports_ditto_ca_cert_env(self) -> None:
        with open(SETUP_TWINS, encoding="utf-8") as fh:
            src = fh.read()
        self.assertIn("DITTO_CA_CERT", src)

    def test_init_setup_urlencodes_special_mqtt_credentials(self) -> None:
        setup_sh = os.path.join(ROOT, "deploy", "compose", "init", "setup.sh")
        # Extract and run the urlencode function via POSIX sh to verify
        # URI/JSON/sed-breaking characters are percent-encoded safely.
        script = (
            f'eval "$(sed -n "/^urlencode()/,/^}}/p" "{setup_sh}")"\n'
            'urlencode "user|name@host:p&ss\\\"/?#%"\n'
        )
        proc = subprocess.run(["sh", "-c", script], capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "user%7Cname%40host%3Ap%26ss%22%2F%3F%23%25")


if __name__ == "__main__":
    unittest.main(verbosity=2)
