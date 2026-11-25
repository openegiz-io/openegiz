# Extended API for Eclipse Ditto

First-party OpenEgiz service adopted from
[`ertis-research/extended-api-for-eclipse-ditto`](https://github.com/ertis-research/extended-api-for-eclipse-ditto)
at commit `b49663dea326854a2323423eaeab7e7f54d325a7` and maintained in this
monorepo from here on (see `NOTICE` at the repository root for provenance and
licensing). High-level decisions: `docs/adr/0002-extended-api-and-plugin-packaging.md`.

Changes against upstream:

- Optional authentication middleware (`src/middleware/auth.ts`, disabled by
  default. When `AUTH_ENABLED=true`, set the `AUTH_TOKEN` shared secret).
- Multi-stage Dockerfile compiling TypeScript to JavaScript: the runtime image
  has no `ts-node` and is multi-arch (`linux/amd64`, `linux/arm64`).
- Pinned dependencies via `yarn.lock` in the image build
  (upstream's `Dockerfile.sample` re-resolved them on every build).
- Unit tests for the auth middleware run without a live stack
  (`yarn test:unit`); the upstream integration suites
  (`yarn test:integration`) still require Ditto and MongoDB.

## Configuration

| Variable | Meaning |
| --- | --- |
| `PORT` | Listen port (default `3001`; compose sets `8080`) |
| `DITTO_URI_THINGS` | Base URL of the Ditto nginx gateway |
| `DITTO_USERNAME_API` / `DITTO_PASSWORD_API` | Ditto API credentials |
| `DITTO_USERNAME_DEVOPS` / `DITTO_PASSWORD_DEVOPS` | Ditto devops credentials |
| `MONGO_URI_POLICIES` | MongoDB URI; when set, `GET /api/policies` is enabled |
| `AUTH_ENABLED` | `true` enforces authentication (default: off) |
| `AUTH_TOKEN` | Required when authentication is enabled. Accepts `Bearer <token>` or Basic auth |

## Local development

    yarn install
    yarn lint            # type-check + auth unit tests
    yarn build           # tsc -> dist/
    yarn start           # node dist/src/app.js
