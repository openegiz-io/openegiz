# Offline Bundle and NAS backup

An Offline Bundle restores a tagged OpenEgiz release with no internet, Git hosting, or container registry. It includes a bare Git mirror containing the release tag and its reachable history, the packaged Helm chart, container image archives, a manifest, SHA-256 checksums, and the restore helper. The image set comes from the Compose Dev and Production Profiles (including the MQTTS overlay) and from the Helm Dev and Production Profiles.

## Export on a connected machine

Install Git, curl, Python 3.10 or later with PyYAML, Docker Compose v2.24.4 or later, Helm v3.20, and [regctl](https://regclient.org/install/) with support for `regctl image export --name`. Fetch the release tag into a checkout that contains the Offline Bundle helper. The helper reads the deployment configuration from the requested tag, so this also works for `v2.0.0-rc.1`, which predates the helper.

```bash
git fetch origin tag v2.0.0-rc.1
python3 scripts/offline-bundle.py export \
  --tag v2.0.0-rc.1 --platform linux/amd64 --platform linux/arm64 \
  --output "$HOME/openegiz-archives"
```

Pass one `--platform` for a smaller archive. Choose the Linux architecture of the Docker engine or Kubernetes node, including when using Docker Desktop. Export needs free space for the staged images and the final tar. It prints the path of the finished archive.

The exporter pulls the OCI chart from GHCR and selects each image from its immutable platform digest. If using the chart and `SHA256SUMS` from GitHub Releases, pass `--chart /path/to/openegiz-2.0.0-rc.1.tgz --chart-checksums /path/to/SHA256SUMS`. The images still come from their registries. Configure Helm and regctl registry credentials on the export host if the release packages require authentication. Registry credentials stay on the export host.

The manifest records the Git tag and commit, the chart checksum and OCI digest when pulled from GHCR, the image inventory by Deployment Profile, and each image's source index, platform manifest, and config digests. The platform archive retains the original image reference and manifest. The classic Docker image store reports the config digest as the image ID, and Docker's containerd image store reports the manifest digest.

To exercise the CLI against a published release, run `python3 scripts/test-offline-bundle.py --tag v2.0.0-rc.1 --platform linux/arm64`. The test exports, verifies, recovers the release, and checks that a corrupted image archive is rejected. Use the runtime sections below to verify restoration on clean, isolated hosts.

## Archive and verify on the NAS

Set `bundle` to the path printed by export before running the commands below. Copy the archive to a versioned NAS directory and verify the NAS copy.

```bash
python3 scripts/offline-bundle.py verify "$bundle"
nas=/mnt/nas/openegiz/v2.0.0-rc.1
mkdir -p "$nas"
cp "$bundle" "$nas/"
python3 scripts/offline-bundle.py verify "$nas/$(basename "$bundle")"
```

Keep a trusted copy of this guide and `scripts/offline-bundle.py` beside the archive. The helper works with the Python standard library for verification and restoration. Use the trusted copy to verify the bundle before using the embedded helper. Keep an independent hash or signed record of the archive where your backup process requires authenticity as well as corruption detection.

Archive the prerequisites for each target architecture too, including the OS and Docker/Compose installers or the k3s materials below, plus Git, Python, Bash, curl, Make, Helm, and kubectl as needed. Back up OpenEgiz volumes or PVC data, credentials, custom values, uploaded 3D Scenes, and TLS material separately. The bundle recreates release software and its default deployment configuration.

To recover the bare Git mirror for local hosting, verify the archive, then extract it into an empty bare-repository directory.

```bash
mkdir openegiz.git
tar -xOf "$bundle" openegiz.git.tar.gz | tar -xzf - -C openegiz.git
git --git-dir=openegiz.git fsck --full
```

## Restore to Docker Compose

Use a clean Docker engine with empty image storage and block external network egress for an isolation test. Keep loopback and Docker's internal networks available. Set `bundle` and `helper` to absolute paths on this host. The helper checks every artifact before restoring the release checkout and importing images with their expected names.

```bash
python3 "$helper" restore "$bundle" --checkout ./openegiz \
  --runtime docker --platform linux/arm64
cd openegiz
export OPENEGIZ_RELEASE=2.0.0-rc.1
bash scripts/compose-env.sh

compose=(docker compose -f deploy/compose/docker-compose.yml \
  -f deploy/compose/docker-compose.release.yml \
  -f deploy/compose/docker-compose.prod.yml)

"${compose[@]}" up -d --no-build --pull never --wait --wait-timeout 900
test "$(docker wait "$("${compose[@]}" ps -a -q init)")" = 0
touch deploy/compose/.prod
bash scripts/compose-wait-ready.sh --prod
PYTHONPATH="$PWD/.offline/paho_mqtt-2.1.0-py3-none-any.whl" make smoke
```

The Production Profile uses Caddy's local CA with `CADDY_TLS=internal`. Use a private hostname resolvable by clients or keep the localhost default. For MQTTS, prepare the certificate files as described in the [Compose guide](docker-compose.md#production-profile), set `MQTTS_ENABLED=true`, and append `-f deploy/compose/docker-compose.mqtts.yml` to `compose`. To use the Dev Profile, drop the Production Profile overlay, omit the `.prod` marker, and run `bash scripts/compose-wait-ready.sh` without `--prod`.

The smoke test uses the archived Paho MQTT wheel to run Example Oven without pip. The separate Example Mine simulator build uses additional dependencies. If you run Example Mine offline, stage its built image separately.

## Bootstrap an offline k3s node

On a connected machine, download the k3s binary, architecture-specific system image archive, and checksum file from the same [k3s release](https://github.com/k3s-io/k3s/releases). Save the installation script at that release tag. For example, stage `k3s-arm64`, `k3s-airgap-images-arm64.tar.zst`, `sha256sum-arm64.txt`, and [install.sh for v1.35.5+k3s1](https://github.com/k3s-io/k3s/blob/v1.35.5%2Bk3s1/install.sh). For amd64 the binary is named `k3s`. Verify the binary and system archive against the release checksums before transferring them. Include any OS packages required by your [k3s air-gap installation](https://docs.k3s.io/installation/airgap), including the SELinux policy packages on hosts that require them.

On the isolated Linux node, keep a default route on the internal interface or follow the k3s guide for a dummy default route. This example uses a single node and port forwarding. Keep Traefik and configure internal TLS Ingress as described in the [Kubernetes guide](kubernetes.md#production-profile) if you need an Ingress.

```bash
sudo install -m 0755 k3s-arm64 /usr/local/bin/k3s
sudo install -D -m 0644 k3s-airgap-images-arm64.tar.zst \
  /var/lib/rancher/k3s/agent/images/k3s-airgap-images-arm64.tar.zst
sudo env INSTALL_K3S_SKIP_DOWNLOAD=true \
  INSTALL_K3S_EXEC='server --disable=traefik --disable=metrics-server --disable=servicelb' \
  sh ./install.sh
sudo k3s kubectl wait node --all --for=condition=Ready --timeout=180s
sudo k3s kubectl -n kube-system rollout status deploy/coredns --timeout=180s
sudo k3s kubectl -n kube-system rollout status deploy/local-path-provisioner --timeout=180s
```

Copy the kubeconfig to the account that will run Helm and keep it readable by that account only.

```bash
sudo install -m 0600 -o "$(id -un)" /etc/rancher/k3s/k3s.yaml "$HOME/openegiz-kubeconfig"
export KUBECONFIG="$HOME/openegiz-kubeconfig"
```

## Restore to k3s or containerd and run Helm smoke

Load the matching architecture on every node that will run OpenEgiz. Run the helper as an account authorized to access the runtime socket. For a standalone containerd installation, use `--runtime containerd` to import into the `k8s.io` namespace on the local containerd endpoint. Set `CONTAINERD_ADDRESS` if your standalone containerd uses a custom socket.

```bash
sudo python3 "$helper" restore "$bundle" --runtime k3s --platform linux/arm64
python3 "$helper" restore "$bundle" --checkout ./openegiz
cd openegiz
```

Create the namespace and set up credentials as described in the [Kubernetes guide](kubernetes.md#production-profile). On a clean test cluster, generate a Secret with the required keys.

```bash
kubectl create namespace twins
kubectl -n twins create secret generic plant-credentials \
  --from-literal=ditto-password="$(openssl rand -hex 24)" \
  --from-literal=ditto-devops-password="$(openssl rand -hex 24)" \
  --from-literal=grafana-admin-password="$(openssl rand -hex 24)" \
  --from-literal=influxdb-admin-password="$(openssl rand -hex 24)" \
  --from-literal=influxdb-token="$(openssl rand -hex 32)" \
  --from-literal=mqtt-username=openegiz \
  --from-literal=mqtt-password="$(openssl rand -hex 24)"

helm upgrade --install plant .offline/openegiz-2.0.0-rc.1.tgz \
  --namespace twins \
  -f charts/openegiz/values-prod.yaml \
  -f .offline/offline-images.values.json \
  --set credentials.existingSecret=plant-credentials \
  --set ingress.enabled=false --wait --wait-for-jobs --timeout=15m

make helm-smoke RELEASE_NAME=plant NAMESPACE=twins SECRET_NAME=plant-credentials
```

Keep the offline values as the last values file to enforce `imagePullPolicy: Never` for all OpenEgiz workloads. For the Dev Profile, omit the Production Profile values and the Ingress override. The Helm smoke test uses local port forwards and checks Telemetry, Grafana and Extended API proxying, and 3D Scene persistence after a pod restart.
