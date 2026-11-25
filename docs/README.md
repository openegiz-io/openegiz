# OpenEgiz Documentation

**New here?** Start with the [Quick start in the root README](../README.md#quick-start-docker-compose): `make up`, then `make example-mine`. To model your own Twins, see the two [Reference Examples](../examples/README.md).

## Architecture Decision Records (ADRs)

Key architectural decisions for OpenEgiz v2.0.0 live in [`docs/adr/`](adr/):

| File | Decision |
|---|---|
| [0001-monorepo-and-v2-naming.md](adr/0001-monorepo-and-v2-naming.md) | Monorepo topology under `openegiz-io/openegiz` and `v2.0.0` `openegiz` naming |
| [0002-extended-api-and-plugin-packaging.md](adr/0002-extended-api-and-plugin-packaging.md) | First-party Extended API and Grafana Plugin Bundle multi-arch packaging |
| [0003-self-contained-helm-chart.md](adr/0003-self-contained-helm-chart.md) | Self-contained Helm v3 chart with Compose parity |
| [0004-two-profile-security-and-offline-independence.md](adr/0004-two-profile-security-and-offline-independence.md) | Dev / Production Deployment Profiles and Offline Bundle independence |

## Engineering notes

Historical design and packaging notes:

| File | What it covers |
|---|---|
| [arm64-audit.md](arm64-audit.md) | Upstream container multi-arch (`arm64`) compatibility audit |
| [notes-extended-api-build.md](notes-extended-api-build.md) | Historical build log for the arm64 Extended API image (superseded by `services/extended-api/`) |
| [notes-mongodb-arm64.md](notes-mongodb-arm64.md) | Historical notes on replacing Bitnami MongoDB on arm64 |
| [notes-rebrand-plugins.md](notes-rebrand-plugins.md) | Vendoring, patching, and SRI-verifying the Grafana Plugin Bundle |
