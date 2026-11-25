#!/bin/bash
# Upload build files to the Unity WebGL nginx pod and print access links

RELEASE_NAME="${1:-openegiz}"
NAMESPACE="${NAMESPACE:-opentwins}" # legacy-helm-v2 (removed in #42)

POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${RELEASE_NAME}-unity-webgl-server" -o jsonpath='{.items[0].metadata.name}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

if [ -z "$POD" ]; then
    echo "Error: Could not find unity-webgl-server pod"
    exit 1
fi

echo "Uploading to pod: $POD"
echo ""

for f in ./build/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = README.md ] && continue
    echo "  Uploading: $name"
    kubectl cp -n "$NAMESPACE" "$f" "$POD:/usr/share/nginx/html/build/$name"
done

echo ""
echo "Access links:"
for f in ./build/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = README.md ] && continue
    echo "  http://${NODE_IP}:30530/build/${name}"
done
