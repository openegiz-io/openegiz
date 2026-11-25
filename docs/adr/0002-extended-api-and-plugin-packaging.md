---
status: accepted
---

# First-party packaging of Extended API and Grafana Plugin Bundle

Instead of building the Extended API from an external upstream repository on every user install or maintaining two forked React frontend repositories for Grafana plugins, OpenEgiz will adopt the Extended API source directly inside the monorepo and package both the Extended API and the rebranded Grafana Plugin Bundle as versioned, multi-arch (`amd64` + `arm64`) container images in GHCR.

The Extended API will use a multi-stage TypeScript-to-JavaScript build (~100 MB runtime image instead of ~528 MB `ts-node`), support optional authentication for explicit exposure, and remain internal-only in the Production Profile because Grafana's plugin proxy reaches it over the private container/cluster network. The Plugin Bundle will continue to be generated reproducibly from the branding patch script with verified SRI hashes and delivered via a minimal init container image, removing insecure `wget --no-check-certificate` downloads from mutable Git branches.

## Considered Options

- **Separate `ditto-extended-api` repository**: Rejected because it splits release versioning and complicates end-to-end CI across Compose and Helm.
- **Rewriting the Extended API or Grafana plugins from scratch now**: Rejected for `v2.0.0` to keep the release focused on platform maturity without delaying delivery for a full UI rewrite.
- **Maintaining forked React plugin repositories**: Rejected due to high frontend maintenance cost for two external plugin codebases.

## Consequences

- `make up` and Helm installs pull prebuilt multi-arch images without compiling external code or fetching unverified URLs at runtime.
- Project ownership and licensing notices for the adopted Extended API remain explicitly documented in `NOTICE`.
