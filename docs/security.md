# Security and hardening

The Dev Profile is for a trusted, single-machine session. Compose binds published ports to `127.0.0.1` by default. Helm leaves its Services on ClusterIP. MQTT and the Extended API permit unauthenticated access in their respective reachable networks by default. Use the Production Profile for shared hosts and clusters.

## Production boundaries

| Boundary | Docker Compose | Kubernetes |
|---|---|---|
| Web traffic | Caddy terminates HTTPS for Grafana, Ditto HTTP/WebSocket, and the 3D Scene server | TLS Ingress routes the same services. Supply your controller, DNS, and certificates |
| MQTT | Authenticated plaintext on 1883, with optional TLS on 8883 | Authenticated ClusterIP Service on 1883. Use a dedicated TLS gateway if you need external access |
| Storage and Extended API | No direct host ports for MongoDB, InfluxDB, or the Extended API | ClusterIP Services with no Ingress routes |
| Grafana proxy | Server-to-server calls through the container network | Server-to-server calls through cluster Services |

Limit network access to trusted publishers and users. MQTT credentials allow access to the broker, so use network restrictions for the plaintext listener and use MQTTS for clients crossing untrusted networks. In a shared cluster, apply NetworkPolicies to restrict access from workloads outside the release. ClusterIP controls external service publication and is reachable by other permitted workloads in the cluster. MongoDB relies on this network boundary.

Grant Grafana access only to users who should use its service credentials through the plugin proxy. Keep the Ditto `devops` credentials restricted to operators. The 3D Scene endpoint serves files to browsers without a login by default. Publish only files suitable for everyone who can reach that endpoint, or add access control at the edge.

Use a secret manager or a protected directory for credentials. Compose stores generated credentials in `deploy/compose/.env` and prints connection details at startup. In Helm, `credentials.existingSecret` keeps secret contents out of values and chart release records. Keep backups of state and credentials in protected storage.

## Extended API authentication

Keep the Extended API internal for standard Grafana deployments. If you deliberately expose it to direct clients, terminate TLS and set `EXTENDED_API_AUTH_ENABLED=true` and `EXTENDED_API_AUTH_TOKEN` in Compose, or `extendedApi.auth.enabled=true` with the Secret key `extended-api-auth-token` in Helm. Clients can send `Authorization: Bearer <token>` or the Basic form documented in the [service README](../services/extended-api/README.md).

When authentication is enabled, the Extended API rejects requests until a token is configured. Grafana's existing routes forward the Ditto Basic credentials. To keep those routes working with Extended API authentication enabled, the configured token must match the decoded credential they send, such as `ditto:<password>`. Verify both the authorized direct path and the Grafana plugin proxy before exposing the service.

Report suspected vulnerabilities through the [security policy](../SECURITY.md).
