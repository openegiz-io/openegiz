#!/usr/bin/env python3
"""
Telemetry generator for the OpenEgiz Oven Reference Example (oven-01, oven-02).

Publishes simulated electrical telemetry via MQTT (Mosquitto) using the Eclipse
Ditto protocol. Features: voltage_v, current_a, active_power_kw, power_factor.
"""

import argparse
import json
import math
import os
import random
import signal
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt


# ── Default configuration ────────────────────────────────────────────
DEFAULT_MQTT_HOST = "localhost"
DEFAULT_MQTT_PORT = 1883
DEFAULT_THING_IDS = [
    "org.openegiz:oven-01",
    "org.openegiz:oven-02",
]
DEFAULT_INTERVAL = 5  # seconds


# ── Realistic value simulation ───────────────────────────────────────

class OvenSimulator:
    """Simulates realistic electrical parameters for an industrial oven."""

    def __init__(self):
        self._step = 0
        # Base values
        self._base_voltage = 220.0
        self._base_current = 20.0
        self._base_pf = 0.92
        # Oven cycle period (in steps) — ~5 minute heating cycle
        self._cycle_period = 60

    def generate(self) -> dict:
        """Generate one set of readings."""
        self._step += 1
        t = self._step

        # Phase in the heating cycle (0 to 2pi)
        phase = (2 * math.pi * t) / self._cycle_period

        # Voltage: ~220V with small grid fluctuations (sigma=2V)
        voltage = self._base_voltage + random.gauss(0, 2.0)
        voltage = round(max(200.0, min(240.0, voltage)), 2)

        # Current: sinusoidal heating cycle (ramp up -> hold -> ramp down)
        # Range roughly 8A to 45A
        cycle_factor = 0.5 + 0.5 * math.sin(phase)  # 0..1
        current = 8.0 + cycle_factor * 37.0 + random.gauss(0, 1.5)
        current = round(max(5.0, min(50.0, current)), 2)

        # Power factor: varies slightly with load
        # Higher load -> slightly better PF
        pf = self._base_pf + 0.05 * cycle_factor + random.gauss(0, 0.01)
        pf = round(max(0.75, min(0.99, pf)), 3)

        # Active power: P = V * I * PF / 1000 (in kW)
        active_power = (voltage * current * pf) / 1000.0
        active_power = round(active_power, 3)

        return {
            "voltage_v": voltage,
            "current_a": current,
            "active_power_kw": active_power,
            "power_factor": pf,
        }


# ── Ditto protocol message builder ──────────────────────────────────

def build_ditto_message(thing_id: str, features: dict) -> dict:
    """
    Build an Eclipse Ditto protocol envelope to update all features.

    Topic format: {namespace}/{name}/things/twin/commands/modify
    Path: /features
    """
    namespace, name = thing_id.split(":", 1)

    now = datetime.now(timezone.utc).isoformat()
    ditto_features = {}
    for feat_name, feat_value in features.items():
        ditto_features[feat_name] = {
            "properties": {
                "value": feat_value,
                "timestamp": now,
            }
        }

    return {
        "topic": f"{namespace}/{name}/things/twin/commands/modify",
        "path": "/features",
        "value": ditto_features,
    }


# ── MQTT publisher ───────────────────────────────────────────────────

class MqttPublisher:
    """Publishes Ditto protocol messages to Mosquitto."""

    def __init__(self, host: str, port: int, thing_id: str):
        self.host = host
        self.port = port
        self.thing_id = thing_id
        # MQTT topic that Ditto's mosquitto-source-connection listens on
        self.topic = f"telemetry/{thing_id}"

        self.client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=f"openegiz-oven-sim-{os.getpid()}-{random.randint(1000, 9999)}",
            protocol=mqtt.MQTTv5,
        )
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.connected = False

    def _on_connect(self, client, userdata, flags, rc, properties=None):
        if rc == 0 or (hasattr(rc, "value") and rc.value == 0):
            self.connected = True
            print(f"Connected to MQTT broker {self.host}:{self.port}")
        else:
            print(f"MQTT connection failed: code={rc}", file=sys.stderr)

    def _on_disconnect(self, client, userdata, flags, rc, properties=None):
        self.connected = False
        print(f"Disconnected from MQTT broker (code={rc})")

    def connect(self):
        """Connect to the MQTT broker."""
        print(f"Connecting to Mosquitto ({self.host}:{self.port})...")
        self.client.connect(self.host, self.port, keepalive=60)
        self.client.loop_start()
        for _ in range(10):
            if self.connected:
                break
            time.sleep(0.5)
        if not self.connected:
            print("Failed to connect to MQTT broker", file=sys.stderr)
            sys.exit(1)

    def publish(self, message: dict):
        """Publish a Ditto protocol message."""
        payload = json.dumps(message)
        result = self.client.publish(self.topic, payload, qos=0)
        result.wait_for_publish(timeout=5)

    def disconnect(self):
        """Disconnect from the broker."""
        self.client.loop_stop()
        self.client.disconnect()


# ── Main loop ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="OpenEgiz Oven Reference Example telemetry generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 data_generator.py
  python3 data_generator.py --interval 2
  python3 data_generator.py --mqtt-host 127.0.0.1 --mqtt-port 1883 --steps 1
        """,
    )
    parser.add_argument(
        "--mqtt-host",
        default=os.environ.get("MQTT_HOST", DEFAULT_MQTT_HOST),
        help=f"MQTT broker host (default: {DEFAULT_MQTT_HOST})",
    )
    parser.add_argument(
        "--mqtt-port",
        type=int,
        default=int(os.environ.get("MQTT_PORT", str(DEFAULT_MQTT_PORT))),
        help=f"MQTT broker port (default: {DEFAULT_MQTT_PORT})",
    )
    parser.add_argument(
        "--thing-ids",
        nargs="+",
        default=DEFAULT_THING_IDS,
        help=f"Ditto Twin IDs (default: {' '.join(DEFAULT_THING_IDS)})",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help=f"Publish interval in seconds (default: {DEFAULT_INTERVAL})",
    )
    parser.add_argument(
        "--steps",
        type=int,
        default=0,
        help="Stop after N publish rounds (0 = run forever)",
    )

    args = parser.parse_args()

    twins = []
    for thing_id in args.thing_ids:
        sim = OvenSimulator()
        pub = MqttPublisher(args.mqtt_host, args.mqtt_port, thing_id)
        twins.append({"id": thing_id, "simulator": sim, "publisher": pub})

    running = True

    def signal_handler(sig, frame):
        nonlocal running
        print("\nStopping oven telemetry generator...")
        running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    for twin in twins:
        twin["publisher"].connect()

    print(f"\nStreaming telemetry for {len(twins)} oven Twins:")
    for twin in twins:
        print(f"  {twin['id']} -> telemetry/{twin['id']}")
    print(f"Interval: {args.interval}s")
    header = f"{'Time':<10} {'Twin':<25} {'Volt (V)':<10} {'Curr (A)':<10} {'Power (kW)':<12} {'PF':<8}"
    print("-" * len(header))
    print(header)
    print("-" * len(header))

    rounds = 0
    count = 0
    try:
        while running:
            ts = datetime.now().strftime("%H:%M:%S")

            for twin in twins:
                readings = twin["simulator"].generate()
                message = build_ditto_message(twin["id"], readings)
                twin["publisher"].publish(message)

                count += 1
                print(
                    f"{ts:<10} "
                    f"{twin['id']:<25} "
                    f"{readings['voltage_v']:<10} "
                    f"{readings['current_a']:<10} "
                    f"{readings['active_power_kw']:<12} "
                    f"{readings['power_factor']:<8}"
                )

            rounds += 1
            if args.steps and rounds >= args.steps:
                break
            time.sleep(args.interval)

    finally:
        for twin in twins:
            twin["publisher"].disconnect()
        print(f"\nPublished {count} telemetry message(s).")


if __name__ == "__main__":
    main()
