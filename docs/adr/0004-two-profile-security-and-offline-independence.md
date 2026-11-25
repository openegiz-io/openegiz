---
status: accepted
---

# Two Deployment Profiles and offline independence

OpenEgiz will ship two explicit Deployment Profiles—a **Dev Profile** preserving single-command `localhost` onboarding, and a **Production Profile** providing a hardened baseline without enterprise identity or high-availability clustering overhead. In the Production Profile, Compose adds a Caddy reverse-proxy overlay for automatic HTTPS/TLS termination across Grafana, the Ditto API, and the 3D Scene server; Helm exposes services strictly via `ClusterIP` and TLS-enabled `Ingress` with `existingSecret` support; both profiles disable anonymous MQTT access and keep MongoDB and the Extended API strictly on the internal network.

All upstream container images will be upgraded to supported, multi-arch releases verified against the Grafana Plugin Bundle, then pinned explicitly for reproducibility. To ensure long-term operational independence from external registries and hosting platforms, OpenEgiz will also provide a repeatable Offline Bundle workflow exporting a git mirror, pinned container image archives, the OCI Helm chart, and SHA-256 checksums for local/NAS archival and air-gapped restoration.

## Considered Options

- **Local-only tool with disclaimers**: Rejected because users need a clear, repeatable path to deploy safely on production hosts.
- **Enterprise SSO (Keycloak) + HA MongoDB/Ditto**: Rejected as premature complexity for `v2.0.0`.
- **Nginx or Traefik in Compose Production Profile**: Rejected in favor of Caddy's minimal automatic-TLS configuration.

## Consequences

- No database or Extended API port is exposed on host interfaces or Kubernetes NodePorts in production deployments.
- Every release can be mirrored to private storage (e.g., NAS) and restored end-to-end without internet access.
