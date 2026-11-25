# OpenEgiz Documentation

Start with the [quick start](../README.md#quick-start-docker-compose). Use the guides below to deploy OpenEgiz and work with Twins.

| Guide | What it covers |
|---|---|
| [Architecture](architecture.md) | How Telemetry, Twin state, history, Grafana, and 3D Scenes fit together |
| [Docker Compose](docker-compose.md) | Dev and Production Profiles, release images, HTTPS, and MQTTS |
| [Kubernetes with Helm](kubernetes.md) | OCI installation, TLS Ingress, and upgrades |
| [Offline Bundle and NAS backup](offline-bundle.md) | Export, verify, and restore OpenEgiz without an external registry |
| [Security and hardening](security.md) | Network boundaries, credentials, and Extended API authentication |
| [Twins and Telemetry](twins-and-telemetry.md) | Creating Twins and publishing and reading Telemetry |
| [3D Scenes](3d-scenes.md) | Serving WebGL files and wiring Twin data into a panel |
| [Reference Examples](../examples/README.md) | Example Mine and Example Oven |
| [Migration](../MIGRATION.md) | Moving data and clients from v1.x to v2.0.0 |
| [Release procedure](releasing.md) | Dry runs, package publication, and the artifact contract for Offline Bundles |

## Architecture Decision Records (ADRs)

The [decision records](adr/) explain the architectural choices behind v2.0.0.

| File | Decision |
|---|---|
| [0001-monorepo-and-v2-naming.md](adr/0001-monorepo-and-v2-naming.md) | Monorepo topology under `openegiz-io/openegiz` and `v2.0.0` `openegiz` naming |
| [0002-extended-api-and-plugin-packaging.md](adr/0002-extended-api-and-plugin-packaging.md) | First-party Extended API and Grafana Plugin Bundle multi-arch packaging |
| [0003-self-contained-helm-chart.md](adr/0003-self-contained-helm-chart.md) | Self-contained Helm v3 chart with Compose parity |
| [0004-two-profile-security-and-offline-independence.md](adr/0004-two-profile-security-and-offline-independence.md) | Dev / Production Deployment Profiles and Offline Bundle independence |

## Engineering notes

| File | What it covers |
|---|---|
| [arm64-audit.md](arm64-audit.md) | Upstream container multi-arch (`arm64`) compatibility audit |
| [notes-extended-api-build.md](notes-extended-api-build.md) | Historical build log for the arm64 Extended API image (superseded by `services/extended-api/`) |
| [notes-mongodb-arm64.md](notes-mongodb-arm64.md) | Historical notes on replacing Bitnami MongoDB on arm64 |
| [notes-rebrand-plugins.md](notes-rebrand-plugins.md) | Vendoring, patching, and SRI-verifying the Grafana Plugin Bundle |
