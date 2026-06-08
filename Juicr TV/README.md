# Juicr TV

Juicr TV is the remote-first Android TV surface for Juicr.

Current goals:

- Landscape-first home shell.
- Large focus targets for remote controls.
- Source gates and guarded playback copy.
- No mobile-only assumptions.
- No provider/source-order, metric, recommendation, or P2P runtime movement.
- Remote navigation must be deterministic: side rail, header controls, poster grids, dialogs, and playback HUD should never lose focus.
- Discovery is a catalog grid, not a Home rail clone. Keep the TV sort lanes aligned with the mobile Discovery catalog.
- TV spacing follows a 12px rhythm where practical; focused items use green outline, selected items use green fill.
- Long poster titles may marquee, but must not clip or overflow.

Preferred checks from the workspace root:

```powershell
python "Scripts\tv_app_doctor.py"
python "Scripts\tv_app_doctor.py" --build --build-timeout 90
```

Avoid raw Flutter, Gradle, analyzer, or formatter commands first when a bounded script exists in `Scripts`.

Manual TV smoke before calling a pass:

- Side navigation: Home, Discovery, Library, Settings; left/right transitions should keep visible focus.
- Discovery: filter opens/closes, down exits the filter, poster grid moves left/right/up/down, first-column left returns to side navigation.
- Details: Watch, trailer, episode selection, and close controls are reachable by remote.
- Playback: Back, play/pause, skip buttons, progress focus, Sources, Settings, and Lock remain reachable and HUD hides predictably.
- Library and Settings should preserve the same focus color and spacing behavior as Home and Discovery.
