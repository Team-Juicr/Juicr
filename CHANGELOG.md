# Changelog

## Unreleased

- Initial public repository structure for Android, TV, and Web app lanes.
- Added repository-level privacy, contribution, release, and security guidance.

## [1.0.1]

### Added

- GitHub Actions release automation now rebuilds the Android universal APK and all supported ABI APKs from the repository.
- Manual release rebuilds can target the current `v1.0.1` tag while using the same signing secret names as the existing release setup.
- Release notes now publish in the Added, Changed, Fixed, Recent work, and Contributors format used by the project release page.

### Changed

- Android release artifacts are collected with stable Juicr names for universal, `armeabi-v7a`, `arm64-v8a`, and `x86_64` APK downloads.
- The release workflow updates an existing GitHub release when rebuilding a tag instead of requiring locally uploaded APKs.
- Repository setup now includes Android CI, Dependabot coverage, issue templates, a pull request template, and a CODEOWNERS placeholder.

### Fixed

- Release publishing no longer stops at an app bundle artifact when the current public release expects APK downloads.
- Manual workflow runs can rebuild the current release from the checked-out repository instead of relying on local release assets.
- Release note generation now fails fast when a tagged changelog section is missing or still contains placeholder text.

### Recent work

- Restored the current `v1.0.1` release path around signed APK artifacts produced by GitHub Actions.
- Aligned Juicr repository automation with the proven release shape while keeping Juicr-specific app folders, artifact names, and privacy rules.
- Added bounded doctors for the release workflow and repository setup so future automation changes can be checked quickly.
