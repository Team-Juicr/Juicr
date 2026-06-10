# Changelog

## Unreleased

- Initial public repository structure for Android, TV, and Web app lanes.
- Added repository-level privacy, contribution, release, and security guidance.

## [1.0.1]

### Added

- GitHub Actions release automation now rebuilds Android and Android TV APKs from the repository.
- Android and Android TV releases now publish universal, `arm64-v8a`, `armeabi-v7a`, and `x86_64` APK downloads for the same `v1.0.1` release.
- The release changelog now separates mobile and TV work so the website can surface version notes cleanly.

### Changed

- Android release artifacts use stable `juicr-android` names, and Android TV release artifacts use matching `juicr-tv` names.
- Android TV is aligned to version `1.0.1` so both app lanes can be rebuilt and published together.
- The release workflow builds Android and TV in separate jobs before publishing the full asset set to the existing GitHub release.

### Fixed

- Android release APKs no longer force close during startup when release minification initializes background app services.
- Release publishing no longer stops at mobile-only artifacts when the current public release also expects TV downloads.
- Manual workflow runs can rebuild the current release from the checked-out repository instead of relying on local release assets.
- The release rebuild no longer risks timing out while producing both Android and TV assets.

### Recent work

- Rebuilt `v1.0.1` with signed Android and Android TV APKs produced by GitHub Actions.
- Organized the release into mobile and TV asset groups with matching ABI coverage.
- Updated repository and website release copy so download pages can point users at the current asset names.

### Contributors

- xC3FFF0E
