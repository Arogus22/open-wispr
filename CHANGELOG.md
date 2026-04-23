# Changelog

All notable changes to this fork are tracked here.

## 2026-04-22 — Phase 1: Audio feedback on record start / stop

### What changed
- Added start/end recording sounds so dictation no longer requires looking at the menu bar to know recording state.
- Default sounds: **Ping** on record start (shown as "Sonar" in pt_PT macOS UI), **Bottle** on record end (shown as "Seixo").
- Both sounds are config-driven, independently toggleable, and accept either a system sound name or a full file path.

### Why
Upstream open-wispr has no audio feedback — there's no way to know the recorder actually started/stopped without glancing at the waveform icon. This adds that missing cue.

### Files touched
- `Sources/OpenWisprLib/SoundPlayer.swift` — new, ~25 lines. Resolves a sound name (via `NSSound(named:)`) or a file path (via `NSSound(contentsOf:)`) and plays async. Silently no-ops on missing/empty config so a bad name never blocks recording.
- `Sources/OpenWisprLib/Config.swift` — added 4 optional fields: `startSound`, `endSound`, `startSoundEnabled`, `endSoundEnabled`. Updated `defaultConfig` to ship Ping/Bottle enabled out of the box.
- `Sources/OpenWisprLib/AppDelegate.swift` — 2 call sites: after `recorder.startRecording()` succeeds in `handleRecordingStart`, and after `recorder.stopRecording()` returns a URL in `handleRecordingStop`. Each respects its `*Enabled` flag.

### External changes
- Stopped brew service: `brew services stop open-wispr`.
- Replaced binary inside the brew-installed .app bundle:
  - `/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr`
  - `/opt/homebrew/Cellar/open-wispr/0.35.0/bin/open-wispr`
  - Backups saved alongside as `*.bak.20260422_184624`.
- Ad-hoc codesigned the new binaries (`codesign --force --sign -`).
- Restarted service: `brew services start open-wispr`.
- Added sound fields to `~/.config/open-wispr/config.json` (existing config preserved, only new keys appended).
- Re-granted **Accessibility** permission to `/opt/homebrew/opt/open-wispr/OpenWispr.app` via System Settings — required because the new ad-hoc signature differs from the original brew signature, so TCC treated it as a new app.

### Known caveats
- A future `brew upgrade open-wispr` or `brew reinstall open-wispr` will overwrite the patched binaries. Rebuild from this source tree and re-swap if that happens.
- The binary is ad-hoc signed (not signed with an Apple Developer cert). If Gatekeeper ever complains, approve via System Settings.

### Rollback
```
cp /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr.bak.20260422_184624 \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr
cp /opt/homebrew/Cellar/open-wispr/0.35.0/bin/open-wispr.bak.20260422_184624 \
   /opt/homebrew/Cellar/open-wispr/0.35.0/bin/open-wispr
brew services restart open-wispr
```

### Verified
Manually: pressed hotkey (Right Option) in toggle mode — heard Ping on start, Bottle on stop, dictation flowed through normally. Confirmed by user on 2026-04-22.
