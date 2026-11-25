---
status: accepted
---

# Monorepo topology under github.com/openegiz-io and v2.0.0 naming purge

OpenEgiz will consolidate into a single canonical repository (`openegiz-io/openegiz`) under the dedicated `openegiz-io` GitHub organization, housing Docker Compose, the Helm chart (published as an OCI artifact to `ghcr.io/openegiz-io/charts/openegiz`), the Extended API service, the Plugin Bundle pipeline, Reference Examples, and English-first documentation (with `README.ru.md` as an entry mirror). Before rewriting Git history to strip large historical binaries, a read-only `openegiz-io/openegiz-v1-archive` repository will preserve the intact `v1.0.4` snapshot and legacy educational materials.

To decouple OpenEgiz cleanly from upstream OpenTwins conventions, `v2.0.0` intentionally breaks backwards compatibility on internal identifiers—replacing `opentwins` with `openegiz` across the InfluxDB organization, MQTT topic prefix (`openegiz/#`), Grafana datasource UID (`openegiz-influxdb`), and Helm chart identity (`openegiz`, release-agnostic)—retaining `ertis-opentwins-app` only where required as a fixed Grafana plugin identifier.

## Consequences

- Contributors and users have one canonical repository, one release cadence, and a ~3–5 MB git clone instead of ~48 MB.
- Existing `v1.x` installations require an explicit migration step documented in `MIGRATION.md`.
