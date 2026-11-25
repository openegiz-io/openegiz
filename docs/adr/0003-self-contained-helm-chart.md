---
status: accepted
---

# Self-contained Helm v3 chart with Compose parity

The Kubernetes deployment will move out of the repository root into a Helm v3 chart (`apiVersion: v2`) built on clean, self-contained Kubernetes manifests rather than vendored or upstream Helm subcharts (such as Bitnami MongoDB, Hono, Kafka, Ditto, or Grafana subcharts).

Vendored subcharts caused repeated arm64 breakage (notably Bitnami MongoDB lacking arm64 images), bloated the repository by >5 MB, hardcoded the release name `opentwins`, and diverged from the Docker Compose stack. A self-contained chart mirrors the Compose topology 1:1 (MongoDB StatefulSet, InfluxDB 2, Mosquitto, Telegraf, Eclipse Ditto services + nginx, Extended API, Grafana with the Plugin Bundle init container, and a PVC-backed 3D Scene server), guarantees multi-arch `amd64` + `arm64` parity, supports arbitrary release and namespace names, and is published as an OCI chart in GHCR.

## Considered Options

- **Upstream `Chart.yaml` subchart dependencies**: Rejected because upstream chart changes and Bitnami image policies introduce arm64 regressions and make Compose/Helm parity fragile.
- **Deprecating Helm in favor of Compose-only**: Rejected because Kubernetes is a first-class deployment target for industrial servers.

## Consequences

- OpenEgiz owns and tests every Kubernetes manifest directly via `helm lint`, `helm template`, and automated `kind` cluster end-to-end smoke tests in CI.
- Dead OpenTwins components (Hono, Kafka, Kafka-ML, Bitnami legacy MongoDB) are permanently removed from the chart.
