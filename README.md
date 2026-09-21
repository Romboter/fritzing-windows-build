# Fritzing Windows Build

A reproducible, security-conscious GitHub Actions build for 64-bit Fritzing on Windows.

This repository builds unmodified source from the official
[`fritzing/fritzing-app`](https://github.com/fritzing/fritzing-app) and
[`fritzing/fritzing-parts`](https://github.com/fritzing/fritzing-parts)
repositories. It produces:

- a portable ZIP;
- a per-user offline installer;
- SHA-256 checksums;
- a machine-readable build manifest and CycloneDX SBOM;
- a corresponding-source bundle; and
- GitHub artifact attestations.

> [!IMPORTANT]
> This is an independent community build system. It is not an official Fritzing
> download and is not affiliated with or endorsed by Fritzing GmbH or the
> Friends-of-Fritzing foundation.

The supplied lock targets the reviewed Fritzing `develop` snapshot that reports
version 1.0.8, plus its matching `fritzing-parts/develop` commit. It is a
development snapshot, not an upstream Fritzing release tag.

## Why this build exists

The workflow is designed to fix the fragile parts of older unofficial Windows
builders:

- Source revisions are locked to full Git commit SHAs.
- Downloaded dependency archives are verified before extraction.
- GitHub Actions are pinned to immutable commit SHAs.
- libgit2 is built as the exact 1.7.1 layout current Fritzing expects.
- `fritzing-parts/parts.db` is generated **before** packaging.
- The installer defaults to `%LOCALAPPDATA%\Programs\Fritzing`, so Fritzing can
  maintain its bundled parts repository without requiring Administrator rights.
- The ngspice DLL, code models, and support files are staged explicitly.
- Both the portable package and a clean silent installer installation are
  smoke-tested before artifacts are published.

## Run a build

1. Create a public GitHub repository from these files.
2. Open **Actions > Build Fritzing for Windows > Run workflow**.
3. Leave `app_ref`, `parts_ref`, and `parts_branch` empty to use the locked
   commits and parts branch.
4. Leave **Create a draft GitHub Release** disabled for the first run.
5. Download the `fritzing-windows-x64-*` Actions artifact after the job passes.

The build runs only when manually dispatched. Ordinary pushes and pull requests
run the fast repository-validation workflow instead of consuming a Windows
runner for a full C++ build.

## Create a release

Run the workflow again with:

- **Create a draft GitHub Release** enabled; and
- a release tag such as `v1.0.8-community.1`.

The workflow creates a **draft**, not a public release. Review the build manifest,
checksums, SBOM, and smoke-test results before publishing it.

## Updating Fritzing

Use full 40-character commit SHAs for release builds. Update the two source refs
in [`config/build-lock.json`](config/build-lock.json), run repository validation,
then run a non-release Actions build. Do not change a dependency URL without also
updating and independently verifying its SHA-256 value.

See [`docs/RELEASING.md`](docs/RELEASING.md) for the complete procedure and
[`docs/DESIGN.md`](docs/DESIGN.md) for the trust model.

## Security properties

The build intentionally has no custom token requirement. It uses the scoped
workflow `GITHUB_TOKEN`. The build job receives only the permissions required to
upload attestations and, when requested, create a draft release.

Network inputs are limited to the repositories and archive URLs recorded in the
lock file, Qt installed by a pinned action, and pinned GitHub Actions. Archive
hash validation is fail-closed.

## What is not promised

- The included binaries are not Authenticode-signed. Windows may show a
  SmartScreen warning for an unsigned community build.
- A passing workflow is strong build evidence, not a substitute for reviewing
  upstream source changes.
- Perfect bit-for-bit reproducibility is not claimed because the GitHub-hosted
  Windows image and Qt binary repository are external build inputs. The exact
  runner image, tool versions, sources, and dependency hashes are recorded.
- Current upstream code restricts automatic parts updates to its stable parts
  branches. A build locked to `fritzing-parts/develop` may need to be rebuilt
  when that branch advances instead of updating the parts library in-app. This
  builder does not hide that by patching Fritzing source.

## License

The build scripts in this repository are available under the MIT License.
Fritzing and the bundled third-party components retain their own licenses. The
workflow includes Fritzing's license files and emits a source bundle to support
redistribution compliance. See [`THIRD_PARTY.md`](THIRD_PARTY.md).
