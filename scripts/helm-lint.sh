#!/usr/bin/env bash
# Static validation for the self-contained Helm v3 chart (charts/openegiz).
# Verifies:
#   - helm lint (Dev & Production profiles, inline secrets & existingSecret)
#   - helm template under non-default release & namespace names
#   - zero hardcoded legacy upstream identifiers outside the fixed Grafana plugin ID
#   - every rendered container image uses an exact pinned x.y.z tag
#   - all default Services are ClusterIP (or headless None) — zero NodePort/LB
#   - 3D Scene server uses a PersistentVolumeClaim (volumeClaimTemplates)
#   - Production Profile template guards reject insecure overrides
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/openegiz"
SECRETS_EXAMPLE="$CHART/secrets.values.yaml.example"
PROD_VALUES="$CHART/values-prod.yaml"
REL="custom-rel"
NS="custom-ns"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Helm lint (Dev & Production, inline secrets & existingSecret)"
helm lint "$CHART" -f "$SECRETS_EXAMPLE" --strict
helm lint "$CHART" --set credentials.existingSecret=external-creds --strict
helm lint "$CHART" -f "$PROD_VALUES" -f "$SECRETS_EXAMPLE" --strict
helm lint "$CHART" -f "$PROD_VALUES" --set credentials.existingSecret=external-creds --strict

echo "Helm template (non-default release=$REL, namespace=$NS)"
helm template "$REL" "$CHART" -n "$NS" -f "$SECRETS_EXAMPLE" > "$tmp_dir/dev.yaml"
helm template "$REL" "$CHART" -n "$NS" --set credentials.existingSecret=external-creds > "$tmp_dir/dev-ext.yaml"
helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" -f "$SECRETS_EXAMPLE" > "$tmp_dir/prod.yaml"
helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=external-creds > "$tmp_dir/prod-ext.yaml"

echo "Checking rendered manifests invariants"
python3 - "$tmp_dir/dev.yaml" "$tmp_dir/dev-ext.yaml" "$tmp_dir/prod.yaml" "$tmp_dir/prod-ext.yaml" <<'PY'
import re
import sys

def check_manifest(path: str, is_prod: bool, is_ext_secret: bool) -> None:
    text = open(path, encoding="utf-8").read()
    # 1. Zero unauthorized legacy identifiers outside the fixed Grafana plugin ID
    legacy_token = "open" + "twins"
    scrubbed = re.sub(r"ertis-opentwins-app", "", text, flags=re.IGNORECASE)
    m = re.search(legacy_token, scrubbed, flags=re.IGNORECASE)
    if m:
        raise SystemExit(f"FAIL {path}: found unauthorized legacy identifier in rendered manifest")

    # 2. Every rendered container image must use an exact x.y.z pin
    images = re.findall(r'^\s*image:\s*"?([^"\s]+)"?\s*$', text, flags=re.MULTILINE)
    if not images:
        raise SystemExit(f"FAIL {path}: no container images found")
    for img in images:
        if ":" not in img:
            raise SystemExit(f"FAIL {path}: image without tag: {img}")
        _, tag = img.rsplit(":", 1)
        if tag == "latest" or not re.match(r"^[0-9]+\.[0-9]+\.[0-9]+([.+_-][0-9A-Za-z.-]+)?$", tag):
            raise SystemExit(f"FAIL {path}: unpinned image tag: {img}")

    # 3. No NodePort or LoadBalancer Services by default
    if re.search(r"^\s*type:\s*(NodePort|LoadBalancer)\b", text, flags=re.MULTILINE):
        raise SystemExit(f"FAIL {path}: unexpected NodePort or LoadBalancer Service")

    # 4. existingSecret suppresses inline Secret creation
    has_secret = bool(re.search(r"^kind:\s*Secret\b", text, flags=re.MULTILINE))
    if is_ext_secret and has_secret:
        raise SystemExit(f"FAIL {path}: Secret rendered despite credentials.existingSecret")
    if not is_ext_secret and not has_secret:
        raise SystemExit(f"FAIL {path}: expected Secret when credentials.existingSecret is empty")

    # 5. Scene server uses StatefulSet + volumeClaimTemplates (PVC)
    docs = [d for d in re.split(r"(?m)^---\s*$", text) if d.strip()]
    scene_sts = [
        d for d in docs
        if re.search(r"(?m)^kind:\s*StatefulSet\b", d)
        and "name: custom-rel-openegiz-scene-server" in d
    ]
    if not scene_sts:
        raise SystemExit(f"FAIL {path}: missing StatefulSet custom-rel-openegiz-scene-server")
    if "volumeClaimTemplates:" not in scene_sts[0]:
        raise SystemExit(f"FAIL {path}: scene-server must be backed by a PersistentVolumeClaim")

    # 6. Production profile specifics: authenticated Mosquitto + TLS Ingress (no Mongo/Extended API)
    if is_prod:
        if "allow_anonymous false" not in text or "password_file /mosquitto/auth/passwd" not in text:
            raise SystemExit(f"FAIL {path}: Production Profile must disable anonymous MQTT and enable password_file")
        if not re.search(r"^kind:\s*Ingress\b", text, flags=re.MULTILINE):
            raise SystemExit(f"FAIL {path}: Production Profile should render Ingress")
        ingress_block = text.split("kind: Ingress", 1)[1]
        if "mongodb" in ingress_block or "extended-api" in ingress_block:
            raise SystemExit(f"FAIL {path}: MongoDB or Extended API must never appear in Ingress")

check_manifest(sys.argv[1], is_prod=False, is_ext_secret=False)
check_manifest(sys.argv[2], is_prod=False, is_ext_secret=True)
check_manifest(sys.argv[3], is_prod=True,  is_ext_secret=False)
check_manifest(sys.argv[4], is_prod=True,  is_ext_secret=True)
print("rendered manifest invariants: ok")
PY

echo "Checking Production Profile & credential template guards"
expect_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: expected failure for: $desc" >&2
    exit 1
  fi
  echo "ok   guard rejected: $desc"
}

expect_fail "missing credentials without existingSecret" \
  helm template "$REL" "$CHART" -n "$NS"
expect_fail "extended API authentication without a shared token" \
  helm template "$REL" "$CHART" -n "$NS" -f "$SECRETS_EXAMPLE" --set extendedApi.auth.enabled=true
expect_fail "production mongodb NodePort" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x --set mongodb.service.type=NodePort
expect_fail "production influxdb NodePort" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x --set influxdb.service.type=NodePort
expect_fail "production extendedApi NodePort" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x --set extendedApi.service.type=NodePort
expect_fail "production anonymous mosquitto" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x --set mosquitto.allowAnonymous=true
expect_fail "production ingress without TLS" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x --set ingress.tls.enabled=false
expect_fail "production ingress TLS with a certificate for only one host" \
  helm template "$REL" "$CHART" -n "$NS" -f "$PROD_VALUES" --set credentials.existingSecret=x \
    --set ingress.tls.secretName= --set ingress.tls.grafanaSecretName=grafana-tls
expect_fail "ingress TLS enabled without any secretName" \
  helm template "$REL" "$CHART" -n "$NS" --set credentials.existingSecret=x --set ingress.enabled=true --set ingress.tls.enabled=true

echo "helm-lint: ok"
