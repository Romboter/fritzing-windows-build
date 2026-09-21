# Security policy

## Supported code

Only the current default branch and its latest tagged build-repository release
are supported.

## Reporting a vulnerability

Use GitHub's private vulnerability-reporting feature when it is enabled. Do not
open a public issue for an exploitable workflow, installer, or supply-chain
problem. Include the affected workflow run, source revisions, and build manifest.

## Trusting a build

Before installing a release:

1. Verify the file against `SHA256SUMS.txt`.
2. Verify the GitHub artifact attestation with GitHub CLI.
3. Inspect `BUILD-INFO.json` for the exact Fritzing and parts commits.
4. Confirm the workflow run originated from the expected repository and branch.

These builds are unsigned unless the repository owner adds a separate signing
process. A hash proves file identity; it does not prove publisher identity by
itself.

