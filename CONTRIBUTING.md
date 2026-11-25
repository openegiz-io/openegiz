# Contributing to OpenEgiz

Use the [bug](.github/ISSUE_TEMPLATE/bug_report.yml) or [feature](.github/ISSUE_TEMPLATE/feature_request.yml) template when opening an issue. Include the release or commit, Deployment Profile, and relevant commands and logs. Remove credentials and private host details from anything you share. Use the [security policy](SECURITY.md) for suspected vulnerabilities.

## Make a change

1. Fork the repository and branch from `main`. Read the [glossary](GLOSSARY.md) and relevant [decision records](docs/adr/).
2. Run `make lint`. For runtime changes, exercise the affected path before and after editing. Start with `make up` or `make up-prod` and `make smoke` for Compose, or the [Helm verification steps](docs/kubernetes.md#verify-and-operate).
3. Update the English guide that covers the change. If the landing information changes, update both root READMEs. Add user-visible changes to the [changelog](CHANGELOG.md).
4. Open a focused pull request and describe the checks you ran. CI runs static checks, the Compose Dev and Production Profiles on amd64 and arm64, and Helm E2E on kind.

When changing an upstream container pin shared by Compose and Helm, review both deployment definitions and keep their versions aligned. The [release procedure](docs/releasing.md) explains how maintainers verify and publish artifacts. Participation in this project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

OpenEgiz code is MIT. Parts derived from OpenTwins retain their Apache-2.0 license. Contributions are released under the licenses of the files they change. See [NOTICE](NOTICE).
