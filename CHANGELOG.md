# Changelog

All notable changes to this fork are tracked here.

## 2026-04-29 — Planning: focus-lock, hotkey UI, meeting recorder; live transcription dropped

### What changed
- No source changes — pure design and roadmap work. Three feature threads opened, one closed.

### Decisions made
- **Focus-lock feature design (Phase 2 candidate).** At record start, snapshot `NSWorkspace.shared.frontmostApplication`. After Whisper transcription completes (NOT at the stop keypress), re-activate that app, wait ~300ms, then paste. Critical timing: the 4–5s of Whisper processing must run with the user's "browsing" app still focused — only the paste moment itself steals focus back.
- Config fields proposed: `targetLockMode` ∈ {`"auto"` (default — refocus only when needed, clipboard fallback if app gone), `"clipboard"` (always copy, no paste), `"off"` (current behavior)}, and `pasteDelayMs` (default 300).
- **Live / real-time transcription: dropped.** Whisper isn't truly streaming; sliding-window (whisper.cpp `stream` style) and VAD-chunked both sacrifice accuracy and add CPU/battery cost. Accuracy chosen over latency.
- **Hotkey-capture UI proposed (Phase 2 candidate).** Hotkey submenu (matches existing Language/Model/Audio Input pattern) with presets + "Custom…" opening a small borderless NSPanel capturing next key or modifier-only key. New file `HotkeyCaptureWindow.swift` ~100 lines + ~30 lines in `StatusBarController.swift` + ~5 lines in `AppDelegate.swift`.

### Discussion — meeting recorder (deferred, not committed)
- User asked about recording meetings (e.g., Google Meet) capturing both system audio and mic.
- Sketch: ScreenCaptureKit (macOS 13+) for system audio, AVAudioEngine for mic, mixed via aggregate device or dual-stream transcribed separately. New "meeting mode" with transcript-file output (not paste) + speaker labels.
- Scope ~3–4 days. Not committed.

### Files touched
- None (planning only).

### Open questions for next session
1. `targetLockMode` default = `"auto"` — confirm?
2. Lock target = frontmost app at *start* press (not stop) — confirm?
3. Fallback feedback (activation failure / clipboard mode): status bar only, distinct sound, or both?
4. `pasteDelayMs` default = 300ms — OK?
5. Bundle hotkey-capture UI with focus-lock as one Phase 2 commit, or separate Phase 2.5?

## 2026-04-24 — Phase 1 pushed to fork + git identity setup

### What changed
- No source changes this session — git hygiene and planning only.
- Pushed Phase 1 (audio feedback) to personal GitHub fork `Arogus22/open-wispr` on `main`.
- Configured privacy-safe git identity globally: name `Arogus`, email `Arogus22@users.noreply.github.com` (GitHub's noreply alias — keeps real name and personal email out of commit metadata).
- Rewrote the initial commit's author with `git commit --amend --reset-author --no-edit` (the first commit had leaked the machine-default identity `Rafael Ramos <arogus@MacBook-Pro-de-Rafael.local>`). Force-pushed with `--force-with-lease`. Commit SHA changed from `867810d` → `3eeb79a`.

### Why
- Fork needs to be public-shareable (and eventually PR-able upstream) without exposing personal identity.
- Using `--force-with-lease` instead of plain `--force` so the push fails safely if any parallel change landed on the remote — no silent clobber.

### Files touched
- None (git metadata only).

### External changes
- Global git config updated: `user.name`, `user.email`.
- Remote `origin` now points at `https://github.com/Arogus22/open-wispr.git`.
- `main` branch on the fork force-pushed once (acceptable for a fresh, unshared branch).

### Discussion — future n8n / Jarvis integration (not implemented)
- Explored wiring open-wispr into the existing n8n "Jarvis" workflow so voice commands can trigger automations.
- Compared wake-word ("Hey Jarvis") vs dedicated hotkey approaches. Chose **second hotkey** for the first iteration — wake-word requires a second always-on listener (Porcupine or openWakeWord) and adds meaningful complexity/resource cost for a personal tool where pressing a key is already acceptable.
- Architectural insight worth preserving: **local Whisper replaces the paid transcription API** in the current Jarvis flow. open-wispr can own the transcription step and POST the resulting text to an n8n webhook, cutting both cost and round-trip latency versus a cloud STT provider.
- Sketch of the plan (deferred): add a "command mode" hotkey. Same recorder, same Whisper model, but on stop instead of pasting into the active app, `POST { text, timestamp, source: "open-wispr" }` to the Jarvis webhook. Dictation hotkey stays unchanged.

### Verified
- `git log` on `Arogus22/open-wispr` shows commit `3eeb79a` authored by `Arogus <Arogus22@users.noreply.github.com>`. No real name anywhere in the history.

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
