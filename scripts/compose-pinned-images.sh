#!/usr/bin/env bash
# Static check: every image in deploy/compose/docker-compose.yml must be pinned
# to an exact upstream version -- a three-part x.y.z tag, optionally with a
# suffix (e.g. 2.7.12-alpine). Floating tags break reproducibility:
# - :latest moves under your feet,
# - major.minor tags (mongo:6.0, nginx:1.25-alpine) silently change patch
#   level, so two deployments of the same commit run different binaries.
# First-party images (ghcr.io/openegiz-io/*) may use :dev, the local-build
# fallback; published ones are pinned by whoever sets the variable.
set -euo pipefail

file="${1:-deploy/compose/docker-compose.yml}"
failures=0

while IFS= read -r entry; do
  lineno="${entry%%:*}"
  raw="${entry#*:}"
  raw="${raw#*image: }"
  raw="${raw%\"}"
  raw="${raw#\"}"
  # Resolve ${VAR:-default} to its default: compose itself substitutes
  # .env values, and the default is what ships when the variable is unset.
  case "$raw" in
    *'${'*) raw="$(printf '%s' "$raw" | sed -E 's/\$\{[^}]*:-([^}]*)\}/\1/g')" ;;
  esac
  image="${raw%% *}"
  tag="${image##*:}"
  repo="${image%:*}"
  if
    # First-party images: :dev is the documented local-build fallback.
    [[ "$repo" == *openegiz-io/* && "$tag" == "dev" ]]
  then
    printf 'ok   %s:%s (%s:%s, first-party dev build)\n' "$repo" "$tag" "$file" "$lineno"
  elif
    [[ "$tag" == latest || ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+_-][0-9A-Za-z.-]+)?$ ]]
  then
    printf 'FAIL %s:%s (%s:%s): tag is not an exact x.y.z pin\n' "$repo" "$tag" "$file" "$lineno"
    failures=$((failures + 1))
  else
    printf 'ok   %s:%s\n' "$repo" "$tag"
  fi
done < <(grep -n 'image:' "$file")

if [ "$failures" -gt 0 ]; then
  printf '%d unpinned image tag(s) in %s\n' "$failures" "$file"
  exit 1
fi
