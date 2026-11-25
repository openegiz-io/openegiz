# Security policy

## Supported versions

Security fixes target the latest stable OpenEgiz release and the active development branch. Upgrade to the latest patch before reporting a suspected issue. Prereleases are for verification. The [v1 archive](https://github.com/openegiz-io/openegiz-v1-archive) is read-only and receives no security fixes.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/openegiz-io/openegiz/security/advisories/new). Include the version or commit, Deployment Profile, affected component, impact, and enough detail for maintainers to confirm the report. Remove credentials and production data. Keep the report private while maintainers investigate and coordinate a fix and a disclosure date with you.

## Deployment boundaries

Use the Dev Profile on trusted local machines. Use the Production Profile for shared networks and managed clusters. Configure TLS, authenticated MQTT, and restricted access to storage and internal services. The [hardening guide](docs/security.md) describes the boundaries and the settings each operator supplies.
