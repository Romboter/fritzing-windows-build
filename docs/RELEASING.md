# Release procedure

## 1. Review upstream

Review changes in `fritzing-app` and `fritzing-parts` between the currently locked
commits and the proposed commits. Do not update a lock solely because a branch
has moved.

## 2. Update the lock

Put full 40-character SHAs in `config/build-lock.json`. If dependency versions
change, obtain archives from their primary project locations and independently
calculate SHA-256 values before editing the lock.

## 3. Validate the repository

Run:

```powershell
pwsh -NoProfile -File .\tests\Test-Repository.ps1
```

Push the change and confirm the `Validate repository` workflow passes.

## 4. Build without releasing

Manually run `Build Fritzing for Windows` with the release option disabled.
Download the artifact and inspect:

- `BUILD-INFO.json`
- `SBOM.cdx.json`
- `SHA256SUMS.txt`
- the portable ZIP contents
- the install and uninstall behavior on a disposable Windows VM

## 5. Create a draft

Run the workflow again with `create_draft_release=true` and a unique tag such as
`v1.0.8-community.1`. Confirm that the resolved source SHAs are identical to the
tested build.

## 6. Verify and publish

Verify checksums and GitHub attestations. Publish the draft only after the final
files pass a clean-VM test.

## Rollback

Keep releases immutable. If a release is bad, mark it as withdrawn, explain why,
and publish a new build number from a reviewed builder commit. Do not silently
replace release assets under an existing tag.

