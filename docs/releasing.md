# Release OpenEgiz

## Verify a release candidate

After the [release workflow](../.github/workflows/release.yml) is on the default branch, dispatch it against the commit's branch. The dry run builds both first-party images for Linux amd64 and arm64, checks their OCI indexes, packages the Helm chart, and saves the chart and its checksum as workflow artifacts.

```bash
gh workflow run release.yml --ref feat/v2.0.0 -f tag=v2.0.0-rc.1
```

Maintainers can run the following commands from the candidate commit to verify GHCR and GitHub Release publication.

```bash
git tag -a v2.0.0-rc.1 -m 'OpenEgiz v2.0.0 release candidate'
git push origin refs/tags/v2.0.0-rc.1
```

The workflow marks this GitHub Release as a prerelease. Run the [Compose](docker-compose.md#use-published-images) and [Helm](kubernetes.md#install-from-ghcr) instructions against the candidate tag and run their smoke tests.

GHCR creates new packages as private. For the first public release, a package administrator must make `extended-api`, `grafana-plugins`, and `charts/openegiz` public in their package settings. If a package already exists, grant this repository's Actions access to publish to it. After the visibility changes, confirm both image pulls and the chart pull from a client without GHCR credentials. See [GitHub's registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Publish a stable release

Move the applicable entries in [CHANGELOG.md](../CHANGELOG.md) from Unreleased into a dated version section. Ensure CI is green for the tagged commit and the prerelease has been verified. Push the annotated `vMAJOR.MINOR.PATCH` tag. Choose a fresh version for a new release. The release workflow accepts SemVer core versions and prerelease identifiers that are valid Docker tags.

The tag triggers image builds and checks their GHCR manifests. The workflow pushes the packaged OCI chart, pulls it back to verify the checksum, and creates a GitHub Release with generated notes and the packaged chart. For a failed first attempt, rerun the failed workflow job after correcting the external cause.

## Artifact names for deployment and Offline Bundle exports

For a Git tag `v<VERSION>`, artifact references use `<VERSION>` without the leading `v`.

| Artifact | Reference |
|---|---|
| Extended API | `ghcr.io/openegiz-io/extended-api:<VERSION>` |
| Plugin Bundle | `ghcr.io/openegiz-io/grafana-plugins:<VERSION>` |
| OCI Helm chart | `oci://ghcr.io/openegiz-io/charts/openegiz` with `--version <VERSION>` |
| Chart release asset | `openegiz-<VERSION>.tgz` |
| Release asset checksums | `SHA256SUMS`, with the chart archive's filename and SHA-256 |

The chart's version and app version both match `<VERSION>`. A matching Compose checkout uses the same first-party tags with `OPENEGIZ_RELEASE=<VERSION>`. Offline Bundle tooling can resolve the remaining pinned images from the release checkout's Compose configuration and packaged chart for each Deployment Profile. The separate [Offline Bundle work](https://github.com/openegiz-io/openegiz/issues/44) will capture those images and their digests alongside the chart and repository mirror.
