#!/bin/sh
# Plugin Bundle init-container entrypoint: copy the rebranded Grafana plugins
# into the plugins volume shared with the Grafana container, then exit 0.
#
# The bundle was patched and SRI-verified at image build time by
# vendor/grafana-plugins/patch-branding.py (see Dockerfile); nothing is
# downloaded here. The target directory is configurable for Helm/Compose
# volume layouts via PLUGINS_DIR.
set -eu

: "${PLUGINS_DIR:=/plugins}"
mkdir -p "$PLUGINS_DIR"

for plugin in ertis-opentwins-app ertis-unity-panel; do
    # Replace, never merge: a stale plugin directory from a previous bundle
    # must not survive next to the new one.
    rm -rf "${PLUGINS_DIR:?}/$plugin"
    unzip -q -o "/bundle/$plugin.zip" -d "$PLUGINS_DIR"
    # Fail loudly rather than let Grafana start against a half-installed
    # plugin: Grafana loads plugins from plugin.json.
    test -f "$PLUGINS_DIR/$plugin/plugin.json"
    echo "installed $plugin -> $PLUGINS_DIR/$plugin"
done

echo "OpenEgiz plugin bundle installed into $PLUGINS_DIR"
