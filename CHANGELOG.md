# Changelog

All notable changes to this fork are tracked here.

## 2026-04-30 — Phase 2: Focus-lock + hotkey UI shipped, plus self-signed cert for stable TCC grants

### What changed

Phase 2 ships two bundled features and replaces the ad-hoc signing pipeline with a self-signed certificate so future builds preserve the Accessibility grant across rebuilds.

**Focus-lock (U1–U3).** At record start, snapshot `NSWorkspace.shared.frontmostApplication` into a `pendingFocusTarget` ivar (filtered against open-wispr itself by `processIdentifier`, robust to `Bundle.main.bundleIdentifier == nil` in SwiftPM brew installs). On Whisper completion, capture target + `focusLockEnabled` + `preserveClipboard` + `pasteDelayMs` into the completion closure (per-recording isolation; toggling menu mid-Whisper affects the next recording, not the in-flight one). If conditions hold (focus-lock on, target alive, screen unlocked, no overlapping recording), `target.activate(options: .activateIgnoringOtherApps)`, wait `pasteDelayMs` (default 500ms), verify the activation took effect via `frontmostApplication.processIdentifier` (defends against macOS 14+ silent activation no-op), then paste. Otherwise paste into current frontmost. Clipboard always carries the transcribed text unless `preserveClipboard=true`.

**Screen-lock detection (U3).** Public `DistributedNotificationCenter` observers for `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` maintain a `screenLocked` ivar. Replaces the private `CGSSessionCopyCurrentDictionary` SPI considered earlier — no SPI surface.

**Menu toggles (U4).** `Focus Lock` (default on) and `Preserve Clipboard` (default off) join `Toggle Mode` in the menu, mirroring the existing checkmark pattern.

**Hotkey UI (U5–U7).** New `Hotkey: <current>` submenu with locked preset list (Right Option, Right Cmd, F13, Cmd+Shift+R) and `Custom…`. Submenu greys out while `state == .recording` (read directly from the existing `State` enum — no new callback). `Custom…` opens a borderless `NSPanel` (`.borderless` + `.nonactivatingPanel` + `canBecomeKey` override + `NSApp.activate(ignoringOtherApps:)` — all mandatory for an `.accessory` app's panel to receive key events) that captures the next keystroke or modifier-only key. Capture state machine handles modifier-only commit on UP edge (Right Option alone), combo commit on `keyDown` (`Cmd+Shift+R`), and live preview during partial holds. Cancellation via Esc, Cmd+Q (intercepted, doesn't terminate), resignKey (click outside), and 5s no-input watchdog. Resume of the global hotkey wired to BOTH `windowWillClose` and `windowDidResignKey` notifications so a panel that loses key without closing still resumes correctly.

**`HotkeyManager.isModifierOnlyKey` whitelist** extended to include keycode 57 (Caps Lock).

**TextInserter parameterized (U2).** `insert(text:restoreClipboard:)` with `restoreClipboard: false` as the new default (transcribed text remains on clipboard after paste). Defensive `guard !text.isEmpty else { return }` at top of function — single source of truth for the empty-text invariant.

### Why

Two daily-use papercuts: (1) switching apps during the 4–5s Whisper window made the paste land in the wrong app, (2) changing the hotkey required hand-editing JSON and restarting the brew service. Phase 2 closes both.

### Decisions worth noting

- **Single `focusLockEnabled` boolean** instead of the original three-mode `targetLockMode` enum (`auto`/`clipboard`/`off`). The user's stated intent collapsed naturally into one behavior — boolean is the smallest correct shape.
- **`preserveClipboard` default = false (clipboard regression is intentional).** Sensitive previously-copied content (passwords, account numbers, MFA codes) gets silently overwritten by dictation. The menu toggle is the explicit escape hatch for sensitive workflows. Documented as a Risk in the plan.
- **`processIdentifier` filter** instead of `bundleIdentifier` for the "snapshot is open-wispr itself" check — robust to SwiftPM executables having no Info.plist and `Bundle.main.bundleIdentifier == nil`.
- **Cross-recording activate guard.** `activate()` is a global side-effect — bringing app A forward while recording B is in progress would steal focus from B. Guarded by `!isPressed` check inside the completion closure.
- **App-level focus lock, not window/field-level.** If the user changes documents within the same app during Whisper, paste lands in the new frontmost window of that app. v1 limitation, explicit in Scope Boundaries.

### Files touched (source — 6 commits, 7 implementation units)

- `Sources/OpenWisprLib/Config.swift` — added `focusLockEnabled`, `pasteDelayMs`, `preserveClipboard` fields + `effectivePasteDelayMs` clamping helper [0, 5000]ms.
- `Sources/OpenWisprLib/TextInserter.swift` — `insert(text:restoreClipboard:)` signature + empty-text guard.
- `Sources/OpenWisprLib/AppDelegate.swift` — `pendingFocusTarget` + `screenLocked` ivars, screen-lock observers, `pauseHotkey()` / `resumeHotkey()` methods, `performFocusLockedPaste()` helper.
- `Sources/OpenWisprLib/StatusBarController.swift` — `Focus Lock` and `Preserve Clipboard` toggles, `Hotkey` submenu with presets and `Custom…`, greying via `State` enum.
- `Sources/OpenWisprLib/HotkeyManager.swift` — `isModifierOnlyKey` whitelist + Caps Lock (57).
- `Sources/OpenWisprLib/HotkeyCaptureWindow.swift` — new file, ~290 lines. Borderless `NSPanel` capture window with state machine for modifier-only / combo / cancel paths.

### Files touched (planning + tooling)

- `docs/plans/2026-04-29-001-feat-phase-2-focus-lock-hotkey-ui-plan.md` — new. Plan went through `ce-plan` → `ce-doc-review` (6 reviewer personas, 19 fixes integrated) → `ce-proof` HITL (formatting normalization only) → `ce-work` execution.
- `scripts/ship.sh` — new. One-command release flow: build, stop service, backup, install, codesign with the cert, restart service.
- `CLAUDE.md` — updated with Phase 2 status and current install procedure.

### External changes (one-time setup that survives across rebuilds)

- **Self-signed code-signing certificate `OpenWispr Local Build`.** Created via `openssl req -x509 ... -addext "extendedKeyUsage=codeSigning"`, imported to login keychain, trust setting `codeSign` set to `trustRoot` via `security add-trusted-cert`. The Accessibility (TCC) grant is keyed to this cert's identity, so future builds signed with the same cert preserve the grant — no more re-toggling Privacy & Security on each rebuild.
- **Bundle re-signed** with the new cert (`codesign --force --deep --sign "OpenWispr Local Build" /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app`). Old ad-hoc signature replaced. Authority shows `OpenWispr Local Build` (not `adhoc`).
- **Backups of pre-Phase-2 binaries** in `/opt/homebrew/Cellar/open-wispr/0.35.0/_backups/` (not inside the bundle this time — earlier attempts placed them inside `Contents/MacOS/` which broke `--deep` codesign). Includes the original Phase 1 binary (`open-wispr.bak.20260422_184624`) and the first Phase 2 ad-hoc swap (`open-wispr.bak.20260430_2023`).
- **`/Applications/OpenWispr.command` shortcut.** Bash one-liner that runs `brew services restart open-wispr`. Custom icon (extracted from `AppIcon.icns` via `sips`/`DeRez`/`Rez`/`SetFile`) attached as resource fork. Extension hidden via `SetFile -a E`. Findable via Spotlight (Cmd+Space → "OpenWispr" → Enter). The `.app` bundle in the Cellar is the actual app; this `.command` is just the relaunch shortcut.
- **Login Item registered** (optional, user-added): `OpenWispr` in System Settings → General → Login Items pointing at `/Applications/OpenWispr.command`. Redundant with the brew LaunchAgent (which already auto-starts at login) — harmless but produces a brief icon flicker at login as the daemon restarts.
- **Accessibility re-granted** to the new cert-signed bundle. This is the **last** re-grant required for normal rebuild flow — future builds via `./scripts/ship.sh` keep the grant.

### Verification

Manual smoke tests passed end-to-end on the dev binary first, then again on the brew-swapped binary:
- Cross-app paste (start in TextEdit, switch to Safari during Whisper, paste lands in TextEdit). ✅
- Clipboard retains transcribed text when `preserveClipboard=false` (default). ✅
- Hotkey rebinding via menu presets (Right Option ↔ Cmd+Shift+R ↔ F13) — re-registers global monitor cleanly. ✅
- `Custom…` panel: capture Right Option, Cmd+Shift+R, Esc-cancel, Cmd+Q-cancel, click-outside-cancel, watchdog. All work. ✅
- Menu greying during toggle-mode active recording. ✅

### Known caveats

- **Future `brew upgrade open-wispr` or `brew reinstall open-wispr` will overwrite the patched binaries** as before. Recovery: re-run `./scripts/ship.sh`.
- **The `.app` bundle is signed with a self-signed cert**, not an Apple Developer cert. Gatekeeper still considers it "from an unidentified developer" if launched outside `launchctl` (e.g., double-clicking the `.app` in Finder triggers the warning). The `.command` shortcut + `brew services` flow bypasses Gatekeeper entirely (launchctl path), so this is invisible in normal use.
- **Accessibility grant is keyed to the cert's public-key hash.** If the cert is ever rotated (deleted + recreated), the grant breaks once and needs re-granting. The `_backups/` and the cert in the keychain are the only state that needs preserving across machines.

### Rollback

Restore the pre-Phase-2 binary:
```
cp /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/open-wispr.app-bin.<TS> \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr
codesign --force --deep --sign "OpenWispr Local Build" \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app
brew services restart open-wispr
```

Or the original Phase 1 binary:
```
cp /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/open-wispr.bak.20260422_184624 \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr
codesign --force --deep --sign "OpenWispr Local Build" \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app
brew services restart open-wispr
```

(Re-codesign with the cert is required either way so the Accessibility grant survives.)

---

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
