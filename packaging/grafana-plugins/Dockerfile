# syntax=docker/dockerfile:1

# OpenEgiz Plugin Bundle init container (issue #38, ADR 0002).
#
# Delivers the two rebranded Grafana plugins (`ertis-opentwins-app`,
# `ertis-unity-panel`) to the Grafana plugins volume: the entrypoint copies the
# bundle into PLUGINS_DIR and exits 0. Compose and Helm run it as a one-shot
# init container; no plugin bytes are downloaded at deploy time.
#
# The builder stage is the single source of truth for plugin content:
# vendor/grafana-plugins/patch-branding.py re-patches the vendored upstream
# archives and --check verifies that the zips committed to the repository
# reproduce exactly (and that every pinned SRI digest matches its chunk), so a
# build fails on any drift between upstream sources, patch output and the
# shipped archives.
#
# Multi-arch: both base images publish linux/amd64 and linux/arm64 manifests,
# and nothing in either stage is architecture-specific; build with
# `docker buildx build --platform linux/amd64,linux/arm64`.

FROM docker.io/library/python:3.12-alpine AS patcher
WORKDIR /src
# plugin sources: upstream archives, patcher, and the logo it embeds
COPY vendor/grafana-plugins vendor/grafana-plugins
COPY openegiz_logo_dark.svg .
# Fails the build on reproducibility or SRI drift; leaves the verified zips
# in vendor/grafana-plugins/.
RUN python3 vendor/grafana-plugins/patch-branding.py --check

FROM docker.io/library/busybox:1.38
LABEL org.opencontainers.image.title="openegiz-grafana-plugins" \
      org.opencontainers.image.description="OpenEgiz Grafana Plugin Bundle init container" \
      org.opencontainers.image.source="https://github.com/openegiz-io/openegiz"
COPY --from=patcher \
    /src/vendor/grafana-plugins/ertis-opentwins-app.zip \
    /src/vendor/grafana-plugins/ertis-unity-panel.zip \
    /bundle/
COPY packaging/grafana-plugins/install-plugins.sh /usr/local/bin/install-plugins
ENV PLUGINS_DIR=/plugins
ENTRYPOINT ["/bin/sh", "/usr/local/bin/install-plugins"]
