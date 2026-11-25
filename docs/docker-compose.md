# Docker Compose deployment

Install Docker Engine or Docker Desktop with Compose v2, Git, Make, and at least 6 GiB of memory available to Docker. For Windows, install [Docker Desktop with WSL2](https://docs.docker.com/desktop/setup/install/windows-install/), enable integration for your Linux distribution, and clone the project into its Linux filesystem.

## Dev Profile

Run these commands from the repository root with Compose v2.20 or newer.

```bash
make up
make example-mine
make smoke
```

`make up` generates credentials on first start in the git-ignored `deploy/compose/.env` and prints the endpoints and login details. The default host bind address is `127.0.0.1`. MQTT on port 1883 accepts anonymous clients in this profile. The Extended API on port 8085 is unauthenticated by default. MongoDB has no published port.

| Endpoint | Default |
|---|---|
| Grafana | `http://localhost:3000` |
| Ditto HTTP API | `http://localhost:8080/api/2` |
| InfluxDB | `http://localhost:8086` |
| MQTT | `localhost:1883` |
| 3D Scene files | `http://localhost:8090/build/<filename>` |

Use `make ps` and `make logs S=<service>` for diagnostics. If a port is busy, change its setting in `deploy/compose/.env` before starting the stack. `make down` stops containers and keeps their data. `make clean` removes Compose volumes and credentials. When Example Mine is active, `make down` and later starts include the simulator. Use `make example-mine-stop` to stop it while keeping the Twins and history.

## Use published images

Check out the matching release tag. Compose v2.24.4 or newer can run the released Extended API and Plugin Bundle images on `amd64` and `arm64`.

```bash
git switch --detach v2.0.0
export OPENEGIZ_RELEASE=2.0.0
make up
make smoke
```

Keep `OPENEGIZ_RELEASE` set in the shell that manages the deployment. The same setting applies to `make up-prod`. The [release overlay](../deploy/compose/docker-compose.release.yml) selects both GHCR images and removes their build contexts. Use the same version in `git switch` and `OPENEGIZ_RELEASE` for upgrades. If you unset the variable, the Make targets build these two images from the checkout. The Example Mine simulator has its own local build.

## Production Profile

Use Compose v2.24.4 or newer. Generate the configuration, then edit `deploy/compose/.env` for the host before starting the stack.

```bash
bash scripts/compose-env.sh
```

- For a private hostname or localhost, set `OPENEGIZ_DOMAIN` to that hostname and retain `CADDY_TLS=internal`. Install Caddy's root CA on the clients that should trust the deployment. After startup, extract it with the command below.
- For a public deployment, point DNS at the server, allow inbound HTTP/HTTPS on ports 80 and 443, and set `OPENEGIZ_DOMAIN=twins.example.com` and `CADDY_TLS=ops@example.com` with your own hostname and contact. Caddy then obtains certificates using ACME.
- The default bind is `OPENEGIZ_PROD_BIND=0.0.0.0`. Choose the server interface if needed. If you change `HTTPS_PORT`, set `GRAFANA_ROOT_URL` to the full external Grafana URL including that port and the trailing slash.

```bash
make up-prod
make smoke
```

Extract the local root CA after starting a deployment with `CADDY_TLS=internal`.

```bash
docker compose -f deploy/compose/docker-compose.yml -f deploy/compose/docker-compose.prod.yml \
  exec -T caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root.crt
```

Caddy serves Grafana at `/`, Ditto HTTP and WebSocket at `/ditto/api/2` and `/ditto/ws/2`, and 3D Scene files at `/build/<filename>`. MongoDB, InfluxDB, the Extended API, Grafana, Ditto nginx, and the 3D Scene server have no direct host port.

The broker requires the generated `MQTT_USERNAME` and `MQTT_PASSWORD`. Ditto, Telegraf, and Reference Examples use those credentials. The default host listener on 1883 is plaintext, so restrict access with your network firewall. For external clients using TLS, put `ca.crt`, `server.crt`, and `server.key` in `deploy/compose/mosquitto/certs/` or set `MQTTS_CERTS_DIR`. Give the broker read access to the files, set `MQTTS_ENABLED=true`, and run `make up-prod` again. The default TLS port is 8883 and enabling it keeps the 1883 listener active.

See [Security and hardening](security.md) for the network and authentication boundaries.
