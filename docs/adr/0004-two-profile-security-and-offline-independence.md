---
status: accepted
---

# Two Deployment Profiles and offline independence

OpenEgiz ships a **Dev Profile** for single-command localhost onboarding and a **Production Profile** for shared deployments. In the Production Profile, Compose adds a Caddy reverse proxy to terminate HTTPS for Grafana, the Ditto API, and the 3D Scene server. Helm uses `ClusterIP` Services, supports TLS-enabled `Ingress`, and can reference an `existingSecret` for credentials. The Production Profile in both deployment methods disables anonymous MQTT and keeps MongoDB and the Extended API internal.

All upstream container images will be upgraded to supported, multi-arch releases verified against the Grafana Plugin Bundle, then pinned explicitly for reproducibility. To ensure long-term operational independence from external registries and hosting platforms, OpenEgiz will also provide a repeatable Offline Bundle workflow exporting a git mirror, pinned container image archives, the OCI Helm chart, and SHA-256 checksums for local/NAS archival and air-gapped restoration.

## Considered Options

- **Local-only tool with disclaimers**: Rejected because users need a clear, repeatable path to deploy safely on production hosts.
- **Enterprise SSO (Keycloak) + HA MongoDB/Ditto**: Rejected as premature complexity for `v2.0.0`.
- **Nginx or Traefik in Compose Production Profile**: Rejected in favor of Caddy's minimal automatic-TLS configuration.

## Consequences

- No database or Extended API port is exposed on host interfaces or Kubernetes NodePorts in production deployments.
- Every release can be mirrored to private storage (e.g., NAS) and restored end-to-end without internet access.
