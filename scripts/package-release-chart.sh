#!/usr/bin/env bash
# Package the chart for a release and check the actual tarball consumers install.
set -euo pipefail

version="${1:?usage: package-release-chart.sh VERSION OUTPUT_DIR}"
output="${2:?usage: package-release-chart.sh VERSION OUTPUT_DIR}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_chart="$root/charts/openegiz"
chart="$output/openegiz-$version.tgz"

mkdir -p "$output"
helm package "$source_chart" --version "$version" --app-version "$version" --destination "$output"

for profile in dev production; do
  args=(--set credentials.existingSecret=verify-creds)
  if [ "$profile" = production ]; then
    args+=(-f "$source_chart/values-prod.yaml")
  fi
  helm lint "$chart" --strict "${args[@]}"
  manifests="$(helm template verify-release "$chart" -n verify-ns "${args[@]}")"
  images="$(awk '/^[[:space:]]+image:/ {gsub(/"/, "", $2); print $2}' <<< "$manifests")"
  for name in extended-api grafana-plugins; do
    image="ghcr.io/openegiz-io/$name:"
    tags="$(awk -v image="$image" 'index($0, image) == 1' <<< "$images" | sort -u)"
    if [ "$tags" != "$image$version" ]; then
      echo "ERROR: the $profile chart does not render the $name:$version image" >&2
      exit 1
    fi
  done
done
