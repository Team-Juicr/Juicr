# Releases

Use this file as the checklist for Juicr GitHub releases.

## Tag Format

- Use tags that start with `v`.
- Example: `v1.0.1`, `v1.0.2`, `v1.1.0`.
- Keep the tag in sync with `Juicr Android/pubspec.yaml`.

## Before Tagging

1. Update the Android app version in `Juicr Android/pubspec.yaml`.
2. Add a matching `CHANGELOG.md` section named `## [X.Y.Z]`.
3. Fill the `Added`, `Changed`, `Fixed`, and `Recent work` sections with real release notes.
4. Run the narrow bounded doctors for the changed lane.
5. Merge the verified `dev` branch into `main`.
6. Commit the version bump, changelog notes, and automation changes together when they are part of the release branch.

## Publish Flow

1. Make sure `main` contains the verified `dev` changes you want to ship.
2. Create or reuse a tag such as `v1.0.1`.
3. Push the tag, or run the Android Release workflow manually with `release_tag` set to the tag.
4. GitHub Actions restores the release signing key from repository secrets.
5. The workflow builds the universal APK and ABI APKs.
6. The workflow generates GitHub release notes from `CHANGELOG.md`.
7. The workflow uploads or replaces the four release APK assets.

## APK Assets

The Android Release workflow publishes:

- `juicr-vX.Y.Z-universal.apk`
- `juicr-vX.Y.Z-armeabi-v7a.apk`
- `juicr-vX.Y.Z-arm64-v8a.apk`
- `juicr-vX.Y.Z-x86_64.apk`

## Release Notes

GitHub releases use this body shape:

```text
## Added

- Short user-facing improvement.

## Changed

- Short user-facing refinement.

## Fixed

- Short user-facing fix.

## Recent work

- Short summary of the most important recent work.

## Contributors

- Contributor name
```

Keep release notes user-facing. Do not include private account, source, device, or playback details.
