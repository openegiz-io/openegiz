# Kubernetes with Helm

Use Helm v3.8 or later, `kubectl`, and a Kubernetes cluster with a default StorageClass or explicitly configured storage classes. The chart creates single-replica services for Linux `amd64` and `arm64` clusters, including k3s and kind. Set the namespace and release name independently of each other.

## Install from GHCR

Check out the same OpenEgiz tag to get the example values and smoke script. Choose a namespace and set values for the credentials.

```bash
git switch --detach v2.0.0
version=2.0.0
chart=oci://ghcr.io/openegiz-io/charts/openegiz

mkdir -p ~/openegiz-deploy
cp charts/openegiz/secrets.values.yaml.example ~/openegiz-deploy/secrets.values.yaml
chmod 600 ~/openegiz-deploy/secrets.values.yaml
```

Replace the placeholders in your copy with strong, distinct values before installing. Generate values with `openssl rand -hex 24`. For Grafana and InfluxDB the admin username is `admin`. Ditto uses `ditto` for the API and `devops` for platform initialization.

```bash
helm upgrade --install plant "$chart" --version "$version" \
  --namespace twins --create-namespace \
  -f ~/openegiz-deploy/secrets.values.yaml --wait --timeout 15m
```

The default chart uses ClusterIP Services and anonymous MQTT. Use the port-forward commands printed by Helm to access it locally. You can also retrieve them with `helm get notes plant -n twins`.

## Production Profile

Create a namespace and supply a Secret managed outside Helm, for example with an external secrets controller. The Secret belongs in the release namespace and uses the keys below.

- `ditto-password`, `ditto-devops-password`, `grafana-admin-password`, `influxdb-admin-password`, and `influxdb-token`.
- `mqtt-username` and `mqtt-password` when enabling MQTT authentication.
- `extended-api-auth-token` when enforcing a shared secret for the Extended API. See the [authentication guide](security.md#extended-api-authentication).

Apply [`values-prod.yaml`](../charts/openegiz/values-prod.yaml) for authenticated MQTT, larger PVC requests, and TLS Ingress. With Ingress enabled, create or arrange issuance of a TLS Secret for all three hostnames in the release namespace. Point DNS to your Ingress controller and replace the example hostnames and class below. For separate certificates, clear `ingress.tls.secretName` and supply the three per-host Secret names instead.

```bash
helm upgrade --install plant "$chart" --version "$version" \
  --namespace twins --create-namespace \
  -f charts/openegiz/values-prod.yaml \
  --set credentials.existingSecret=plant-credentials \
  --set ingress.className=nginx \
  --set ingress.hosts.grafana=grafana.example.com \
  --set ingress.hosts.ditto=ditto.example.com \
  --set ingress.hosts.sceneServer=scenes.example.com \
  --set ingress.tls.secretName=plant-tls \
  --wait --timeout 15m
```

Grafana uses its own hostname, Ditto serves `/api/2` and `/ws/2` on its hostname, and the 3D Scene server serves `/build/<filename>` on its hostname. For an internal deployment without an Ingress controller, use the same Production values with `--set ingress.enabled=false` and forward the required ports. MQTT stays on a separate ClusterIP Service. For an external MQTT client, provide a dedicated TLS gateway or private network access.

## Verify and operate

```bash
make status RELEASE_NAME=plant NAMESPACE=twins
make endpoints RELEASE_NAME=plant NAMESPACE=twins
make helm-smoke RELEASE_NAME=plant NAMESPACE=twins SECRET_NAME=plant-credentials
```

Omit `SECRET_NAME` when Helm creates the Secret. The smoke test forwards local ports, sends Telemetry, checks Ditto, InfluxDB, and Grafana proxy responses, and verifies that a file survives a 3D Scene pod restart. The invoking Kubernetes identity needs access to the release Secret, pod port forwarding, and deletion of the scene pod for that restart check. See the [3D Scene guide](3d-scenes.md) for uploads.

For source work, use `charts/openegiz` as the chart path, or run `make install` with `RELEASE_NAME`, `NAMESPACE`, and either `SECRETS_FILE` or `EXISTING_SECRET`. Source-based CI loads local images and sets `extendedApi.image.tag` and `grafana.pluginsImage.tag` to their local tag.

## Upgrade an existing v2 release

Back up the datasets and credentials. Check out the new tag and run `helm upgrade` for the same release and namespace, passing the new `--version` and your values again. The chart uses its app version for both first-party images. Remove explicit image tag overrides if you want the new chart to select them. Reapply your original Secret reference. Review storage sizes and classes separately because Kubernetes restricts changes to StatefulSet volume claim templates.

Review `helm history plant -n twins` and run the smoke test after upgrading. `helm rollback` can restore an earlier chart revision. If a component changed its on-disk format, follow its recovery procedure using the backup. For v1, use the [migration guide](../MIGRATION.md).
