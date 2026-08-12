# Juicr Android Changelog

## Unreleased - dev

This development update is a broad mobile stability and parity pass covering
catalog browsing, library behavior, native playback, progress integrity,
subtitles, Live TV, add-ons, diagnostics, and Android platform integration.

### Native playback engines

- Stabilized HLS playback through both libVLC and Media3.
- Stabilized direct and account-backed MP4 playback through both engines.
- Kept Auto as the default engine selection while retaining explicit libVLC
  and Media3 choices for testing and advanced users.
- Added bounded startup ownership so stalled acquisition work cannot leave the
  player indefinitely on Preparing.
- Added generation-scoped cancellation and publication guards so replaced or
  expired playback attempts cannot overwrite the active session.
- Added transactional source replacement: a candidate must initialize and
  prove playback before it replaces the retained source.
- Hardened post-promotion cleanup so disposal failures from superseded drivers
  cannot roll back a successfully proved seek, source switch, or recovery.
- Improved native driver and transport disposal across route exit, source
  replacement, failed startup, recovery, and app lifecycle transitions.
- Preserved explicit engine independence and prevented unintended Media3 or
  libVLC fallback when a specific engine is selected.

### HLS reliability

- Added bounded HLS playlist and segment preflight before native initialization.
- Added continuous MPEG-TS relay support with real media-byte validation.
- Added startup lead accounting and bounded buffering before native handoff.
- Improved redirect, range-request, oversized-segment, malformed transport,
  timeout, and connectivity classification.
- Added cancellation-aware relay ownership so old sessions cannot continue
  downloading or publishing after replacement.
- Added source quarantine and fresh recovery for unreadable or expired HLS
  sessions without repeating equivalent aliases.
- Improved cadence, frozen-clock, renderer-drift, and persistent-buffering
  detection while protecting healthy playback from premature replacement.
- Added truthful loading and recovery states instead of leaving a blank or
  indefinitely opening player surface.

### Seeking, skipping, and source switching

- Restored reliable backward and forward seeking for libVLC continuous-TS HLS.
- Added same-source reopen transactions for streams that cannot seek directly.
- Preserved the active controller until the replacement reaches startup proof.
- Added exact generation ownership for rapid or overlapping seek requests.
- Prevented stale pre-seek clocks from being persisted during a seek transaction.
- Restored the previous proved anchor and playback state when a seek fails.
- Added source-switch anchor preservation so quality or mirror changes resume
  from the user's current position rather than restarting at zero.
- Hardened paused-versus-playing intent across seek and source transactions.
- Added bounded skip-window handling for Media3 VOD playback.

### Progress, resume, and completion

- Unified progress ownership across libVLC, Media3, HLS, MP4, and add-on streams.
- Preserved the highest credible resume anchor when engines or transports change.
- Prevented zero, regressed, uninitialized, unstable, or stale clocks from
  overwriting valid saved progress.
- Added credible-clock checks for renderer drift, buffering, and incomplete
  metadata before saving progress or completion.
- Kept Start over as an explicit user action instead of an implicit reset.
- Kept Resume playback as the default prompt behavior for saved VOD progress.
- Improved completion and Continue watching duration handling.
- Preserved exact series season and episode identity during resume and recovery.
- Restored retained playback UI when next-episode acquisition is cancelled or
  returns no valid target.

### Subtitles and audio

- Preserved subtitle descriptors through native source selection and recovery.
- Added subtitle grouping, loading, cue parsing, and session replacement guards.
- Kept subtitle timing, size, color, background, position, opacity, and delay
  settings available across supported native playback paths.
- Prevented stale subtitle tracks from surviving an exact source or episode change.
- Verified active audio on HLS and MP4 controls through libVLC and Media3.
- Improved audio-track and media-load diagnostics without exposing private media
  or account details.

### P2P and account-backed playback

- Added local P2P bridge preparation for both libVLC and Media3.
- Added bounded peer discovery, metadata acquisition, piece readiness, and local
  byte-range checks before handing a P2P stream to a native engine.
- Added dead-swarm detection so unavailable media settles truthfully instead of
  waiting indefinitely.
- Added Wi-Fi and playback-policy checks plus safe source-priority controls.
- Added progress protection for P2P startup, retries, engine changes, and fallback.
- Verified account-backed MP4 playback through both native engines.
- Kept direct and account-backed streams ahead of optional P2P sources unless the
  user explicitly enables advanced source priorities.

#### Known No-Debrid limitation

- No-Debrid playback is implemented and has produced playable media in prior
  tests, but availability depends on the selected swarm having reachable peers,
  metadata, and readable pieces within the route deadline.
- A final Bumblebee sample found zero seeds for several candidates. One libVLC
  candidate eventually produced readable pieces, but too late for the bounded
  startup window; the Media3 sample did not obtain usable peers in time.
- This is treated as a best-effort beta capability. The app fails closed with a
  truthful unavailable state, preserves saved progress, and does not interpret a
  dead or slow swarm as a native decoder failure.

### Player experience

- Added generation-owned HUD mount verification for the actual left skip,
  play/pause, and right skip controls.
- Prevented hidden or partially animated controls from being reported as ready.
- Improved HUD reveal, hide, lock, focus, and transport-control lifecycle.
- Added reliable player-surface foreground and lifecycle handling for libVLC.
- Preserved nonblack video and active audio during validated playback transitions.
- Improved opening, preparing, source search, unavailable, seek, and recovery copy.
- Kept player diagnostics neutral and redacted.

### Home, Discovery, and catalog

- Improved Home catalog hydration and warm-snapshot freshness handling.
- Added title-wheel and logo hydration guards with stable cached artwork behavior.
- Prevented stale asynchronous catalog responses from replacing fresher content.
- Improved Discovery and catalog auto-load ownership.
- Kept server-backed catalog data authoritative instead of inventing local titles.
- Improved details-page playback acquisition and verified-cache fallback behavior.
- Added season-selection ownership so stale season requests cannot replace the
  user's current selection.

### Library and Live TV

- Improved the Library section selector and semantic navigation.
- Preserved saved movies, series, Continue watching, completed items, and lists.
- Improved exact progress and duration presentation in Continue watching.
- Kept Live TV as a distinct saved-content type rather than treating channels as
  movies or VOD completion entries.
- Verified saved Live TV channels can open exact details and native playback.
- Preserved captions and nonblack video on the audited Live TV control.

### Settings, add-ons, and guidance

- Kept Native player enabled with Auto engine selection as the safe default.
- Audited Playback, Add-ons, Battery and data, Advanced, and Player Guide pages.
- Preserved Advanced playback controls for retry timing, startup behavior,
  progress integrity, P2P consent, and optional source priorities.
- Kept advanced P2P behavior opt-in and guarded by user consent.
- Preserved add-on state without exposing private configuration in diagnostics.
- Updated native playback behavior covered by the in-app Player Guide contracts.

### Android platform and diagnostics

- Improved Media3 load-error classification and emulator decoder compatibility.
- Prefer a software AVC decoder only on the Android emulator when the known
  goldfish hardware decoder would render corrupted scanlines; real devices keep
  their normal decoder ordering.
- Improved app-exit and native-engine interruption classification.
- Prevented app updates, force-stops, and expected lifecycle transitions from
  being mislabeled as crashes.
- Improved notification scheduling and Android activity integration.
- Expanded redaction of source, add-on, request, and playback diagnostics.
- Added bounded diagnostics for startup stage, cadence, transport activity,
  progress decisions, recovery, and terminal settlement.

### Verification

- Added focused model, coordinator, relay, route-owner, HUD, identity, request,
  lifecycle, recovery, progress, catalog, Library, and diagnostics tests.
- Added adversarial tests for stale attempts, overlapping switches, late drivers,
  disposal failures, cancellation, route deadlines, and progress rollback.
- Verified the final staged APK with a four-cell playback matrix: built-in HLS
  and account-backed MP4 through libVLC and Media3.
- Verified build and preserve-data installation on the Android emulator.
- Completed Android, TV, Worker, resolver, privacy, analyzer, and contract guards.
