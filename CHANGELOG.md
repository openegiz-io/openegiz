# Changelog

This file records notable changes to OpenEgiz. It follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Production Profile for Compose with Caddy HTTPS, authenticated MQTT, and an optional MQTTS listener.
- Self-contained Helm v3 chart with TLS Ingress support, externally managed credentials, and persistent storage for 3D Scenes.
- Tag-driven releases with multi-architecture Extended API and Plugin Bundle images and an OCI Helm chart.
- Checksum-verified Offline Bundle export and restore for Docker, containerd, and k3s.
- Example Mine and Example Oven Reference Examples, plus English deployment, security, and migration guides.

### Changed

- Adopted the Extended API into the repository and packaged the Grafana plugins in a reproducible Plugin Bundle.
- Pinned the upgraded stack, including Eclipse Ditto 3.8, MongoDB 8.0, and Grafana 12.
- Changed the Twin Event topic prefix and InfluxDB organization to `openegiz` and the Grafana datasource UID to `openegiz-influxdb`. See the [migration guide](MIGRATION.md) for the v2 breaking changes.

### Removed

- Legacy Helm subcharts, host-specific defaults, and educational material. The [v1 archive](https://github.com/openegiz-io/openegiz-v1-archive/tree/v1.0.4) preserves the historical snapshot.

[Unreleased]: https://github.com/openegiz-io/openegiz/commits/main/
