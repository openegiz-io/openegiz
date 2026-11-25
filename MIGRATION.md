# Migrate from OpenEgiz v1.x to v2.0.0

Use a new v2 deployment alongside v1. The [read-only v1 archive](https://github.com/openegiz-io/openegiz-v1-archive/tree/v1.0.4) contains the old deployment and examples. The v2 chart is a new chart with different resource names, services, and storage. Treat the move as a data migration and keep the old deployment available until verification is complete.

## Before you start

1. Record the v1 versions, credentials, endpoints, MQTT clients, and datasource settings. Take database backups or consistent volume snapshots. Export Grafana dashboards, your Ditto Policies and Twin documents, connection settings, and any 3D Scene files. List all Twin IDs using paginated Ditto searches and export each Twin and each referenced Policy. Store the exports and secrets securely.
2. Decide which Twin IDs should stay the same. If changing any IDs or namespaces, prepare a mapping for dashboards, historical tags, Telemetry publishers, Twin references, and 3D Scene object names.
3. Start v2 with new volumes or in a new Kubernetes namespace. If running Compose alongside the old stack on the same host, pick free host ports and an independent Compose project or use a separate host. See [Compose](docs/docker-compose.md) or [Kubernetes](docs/kubernetes.md).

## What changed

| Contract | v1.x | v2.0.0 |
|---|---|---|
| MQTT Twin Events | `opentwins/#` | `openegiz/#` for Twin Events and `telemetry/#` for incoming commands |
| InfluxDB organization | `opentwins` | `openegiz` with bucket `default` |
| Grafana InfluxDB datasource UID | `opentwins-influxdb` in Compose or the UID assigned by legacy Grafana | `openegiz-influxdb` |
| Grafana plugin identifiers | `ertis-opentwins-app`, `ertis-unity-panel` | Same IDs, shipped by the Plugin Bundle |
| Helm | Legacy `opentwins` chart and host-oriented NodePorts | `openegiz` Helm v3 chart, release-derived names, ClusterIP Services and optional TLS Ingress |
| Compose ingress | Ditto and scene servers on separate local ports | Production overlay under `deploy/compose/` routes Ditto under `/ditto` and scene files under `/build` through Caddy |
| Integrations | Optional legacy Hono, Kafka, Kafka-ML, and Hermes components | Use the MQTT and HTTP interfaces for v2 integrations |

## Move state and switch clients

1. **Policies and Twins.** Review old Policy subjects against the v2 identities, including `nginx:ditto` for the default Telemetry connection. Restore custom Policies with the Ditto v2 Policies API first, then create the Twins with their `policyId` through the Ditto Things API. Preserve writable attributes and features and omit server-managed fields from the input. Leave the new baseline `default:basic_policy` and generated MQTT connections in place unless you intentionally customize them. Recreate custom connection settings with the v2 URLs and credentials.
2. **Telemetry history.** Export old series in a format that preserves timestamps, measurement names, fields, and tags such as `thingId`. Import to the v2 `openegiz` organization and the appropriate bucket, normally `default`. Validate counts, time ranges, and sample points in Grafana. A restored v1 InfluxDB volume can still contain the old organization and token. Use an isolated restore to retrieve or migrate that data. To reuse MongoDB data files directly, first upgrade them using MongoDB's supported major-version sequence.
3. **Grafana and 3D Scenes.** Import custom dashboards and update datasource UIDs, bucket names, and Twin ID filters. Copy the scene files into `build/` for Compose or upload them to the Kubernetes PVC using the [3D Scene guide](docs/3d-scenes.md). Update external scene file URLs to the new endpoints.
4. **Publishers and subscribers.** Point publishers at the new broker and set MQTT authentication for the Production Profile. Switch subscribers and downstream rules to `openegiz/#`. Update direct Ditto HTTP and WebSocket URLs. For normal Grafana access use its provisioned proxy.
5. **Verify and cut over.** Run `make smoke` for Compose or `make helm-smoke` for Kubernetes. Check migrated Twin IDs, Policies, historical queries, dashboards, and scenes. Pause writes for the final export or delta transfer, then switch producers, consumers, and user-facing DNS together. Preserve the v1 volumes and backups until the v2 deployment has been accepted. For rollback, redirect clients to v1 and account for any writes that occurred after the cutover.

An Offline Bundle archives deployable artifacts. Runtime state, configuration, and credentials need their own backups.
