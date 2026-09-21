# Build design and trust model

## Build flow

1. Check out this builder at the workflow commit.
2. Resolve the requested Fritzing and parts refs, then record their exact SHAs.
3. Download locked dependency archives and verify every SHA-256 hash.
4. Build zlib, libgit2, QuaZip, and Clipper with MSVC.
5. Build Fritzing with qmake and nmake.
6. Stage the Qt runtime, application data, ngspice runtime, and parts repository.
7. Generate and validate `fritzing-parts/parts.db` in staging.
8. Generate build metadata, an SBOM, a portable ZIP, and an offline installer.
9. Install the installer silently into a clean temporary directory and smoke-test
   the installed result.
10. Hash and attest the final artifacts. Optionally create a draft release.

## Important choices

### Per-user installer

The installer uses `%LOCALAPPDATA%\Programs\Fritzing` and HKCU file associations.
This avoids requiring elevation and leaves the bundled Git parts repository
writable by the user. Older builders installed under `Program Files` while
omitting `parts.db`, which forced a one-time elevated Fritzing launch.

### Offline-only installer

There is no online installer. An online bootstrapper adds a second supply-chain
event during installation and must securely bind the downloaded parts package to
the application build. The offline installer is larger but deterministic and
can be fully tested in CI.

### Full parts Git repository

The staging tree retains `.git` and verifies its `HEAD`. Fritzing uses libgit2 to
identify and update the parts repository. Both archive creation and installer
testing explicitly verify that `.git/HEAD` survived packaging.

The package also restores the named branch recorded as `packagedBranch` in the
lock file. Source acquisition uses a detached commit for reproducibility, but a
detached parts repository would break Fritzing's remote-reference comparison.

### Generated parts database

Fritzing runs in database-service mode during CI. The workflow requires a
non-empty SQLite database with the expected header before packaging. The
installed copy is checked again after a clean silent install.

### Pinned but reviewable inputs

GitHub Actions use immutable commit SHAs. Application and parts defaults use full
commit SHAs. Archive dependencies have fixed hashes. A manual test build may use
another safe Git ref; its resolved commit is still recorded in `BUILD-INFO.json`.

## Remaining trust boundaries

- GitHub-hosted Windows runner images
- GitHub's Actions service
- the pinned `install-qt-action` code and Qt download service
- Microsoft build tools preinstalled on the runner
- Inno Setup and 7-Zip preinstalled on the runner image

The build manifest records available runner and tool versions so unexpected
changes are visible. Qt binary archives are installed by `aqtinstall`; unlike the
source dependencies, this repository does not independently maintain Qt archive
hashes.
