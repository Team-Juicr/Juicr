# Contributing

Juicr is publicly viewable, but it is not an open-source project. External contributions are accepted only when explicitly invited by Team Juicr.

## Ground Rules

- Use `dev` for active development. Open feature, fix, and dependency PRs against `dev` first, then merge `dev` into `main` only when the release/stable branch is ready.
- Keep user-facing copy neutral and product-safe.
- Do not expose private account, source, device, or playback details.
- Keep diagnostics redacted with safe summaries and timing evidence.
- Keep platform-specific build output out of the repository.
- Keep changes scoped to the app lane being edited.

## App Lanes

- `Juicr Android`: mobile app.
- `Juicr TV`: TV app.
- `Juicr Web`: web/PWA app.

Each lane owns its UI and build process. Shared behavior should preserve Juicr's source-gated posture.

## Branch Flow

- `main` is the stable branch used for releases and public-facing repo state.
- `dev` is the integration branch for active development.
- Dependabot opens dependency updates against `dev`.
- Merge `dev` into `main` after focused checks pass and release notes are ready.
