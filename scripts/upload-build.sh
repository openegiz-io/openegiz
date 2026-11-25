#!/usr/bin/env bash
# Upload compiled 3D Scene WebGL build files to the PVC-backed scene-server pod.
set -euo pipefail

RELEASE_NAME="${1:-${RELEASE_NAME:-openegiz}}"
NAMESPACE="${NAMESPACE:-openegiz}"

POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/component=scene-server" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$POD" ]; then
  echo "Error: Could not find scene-server pod for release=${RELEASE_NAME} in namespace=${NAMESPACE}" >&2
  exit 1
fi

echo "Uploading 3D Scene build files to pod: $POD (namespace=$NAMESPACE)"
echo ""

uploaded=0
for f in ./build/*; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  [ "$name" = README.md ] && continue
  echo "  Uploading: $name"
  kubectl cp -c scene-server -n "$NAMESPACE" "$f" "$POD:/usr/share/nginx/html/build/$name"
  kubectl exec -c scene-server -n "$NAMESPACE" "$POD" -- chmod 0644 "/usr/share/nginx/html/build/$name"
  uploaded=$((uploaded + 1))
done

if [ "$uploaded" -eq 0 ]; then
  echo "No build files found in ./build/ (excluding README.md). Run 'make unity-demo' or 'make copy-build SRC=...' first."
  exit 0
fi

echo ""
echo "Uploaded $uploaded file(s) to persistent PVC storage on $POD."
echo "Files are served under /build/<filename> and survive pod restarts and upgrades."
