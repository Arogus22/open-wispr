---
title: "feat: Phase 2 — Focus-lock and Hotkey-Capture UI"
type: feat
status: active
date: 2026-04-29
deepened: 2026-04-29
---

# feat: Phase 2 — Focus-lock and Hotkey-Capture UI

## Summary

Adds focus-lock (snapshot frontmost app at record start, re-activate after Whisper completes, paste with a 500ms delay, always leave transcribed text on clipboard by default) and a menu-driven hotkey-capture UI (preset submenu plus a `Custom…` borderless `NSPanel` that captures the next keystroke or modifier-only key). Bundled in the same release. Three new config fields and two new menu toggles, mirroring the existing `Toggle Mode` pattern.

***

## Problem Frame

Today the transcription pastes into whatever app is frontmost when Whisper finishes — so switching apps during the 4–5s of Whisper processing breaks the workflow. There is also no in-app way to change the recording hotkey: users must hand-edit `~/.config/open-wispr/config.json` and restart the brew service. Both papercuts hit daily-use dictation.

***

## Requirements

* R1. At record start (key-down in press-and-hold, or first toggle press), snapshot `NSWorkspace.shared.frontmostApplication`. If the snapshot's `processIdentifier` matches `ProcessInfo.processInfo.processIdentifier` (i.e., the snapshot is open-wispr itself), discard the snapshot.

* R2. After Whisper transcription completes, when `focusLockEnabled` is true, the snapshot target is alive, the screen is not locked, and no other recording is currently in progress, call `targetApp.activate(options: .activateIgnoringOtherApps)`, wait `pasteDelayMs`, then run the paste flow.

* R3. By default, the transcribed text is left on the clipboard after paste. When `preserveClipboard` is true, the pre-recording pasteboard is restored instead (legacy behavior). The escape hatch exists for users handling sensitive previously-copied content (passwords, account numbers, MFA codes).

* R4. Skip activation and paste when the screen is locked. Detect lock state via the public `DistributedNotificationCenter` notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`, maintained as an in-memory `screenLocked: Bool` ivar on `AppDelegate`. The transcribed text still lands on the clipboard per R3.

* R5. Empty transcription (silence) and Whisper errors leave the clipboard untouched. The empty-text guard lives both at the call site (no `inserter.insert` call when `text.isEmpty`) and inside `TextInserter.insert` itself (defensive guard against future call sites).

* R6. Add a `Hotkey` submenu to the menu bar with a small set of presets and a `Custom…` item, mirroring the existing `Language` / `Model` / `Audio Input` submenu pattern.

* R7. `Custom…` opens a borderless `NSPanel` that captures the next `keyDown` or `flagsChanged` event, parses it via the existing `KeyCodes.parse`, persists via `Config.save`, and re-registers the global monitor via the existing `applyConfigChange` flow.

* R8. While the capture panel is open, the global hotkey listener is paused so that pressing the current recording hotkey is captured as a rebind, not a recording trigger. Escape, `Cmd+Q`, resign-key, and a 5-second no-input watchdog all cancel without changing config.

* R9. Add two menu toggles: `Focus Lock` (default on) and `Preserve Clipboard` (default off), each with a checkmark following the existing `Toggle Mode` item pattern.

* R10. While the recording state is `.recording` (toggle-mode active recording), Hotkey-related menu items are disabled to prevent rebind mid-recording. State is read from the existing `StatusBarController.state` enum, not via a new callback channel.

***

## Scope Boundaries

* The original three-mode `targetLockMode` enum (`auto` / `clipboard` / `off`) is replaced by a single `focusLockEnabled` boolean.

* **Focus-lock targets the application, not the specific window or text field.** If the user changes documents/windows within the same app during Whisper processing, the paste lands in the new frontmost window of that app.

* **Clipboard regression with** **`preserveClipboard: false`** **(the default) is intentional.** Previously-copied sensitive content (passwords, account numbers, MFA codes) is silently overwritten by dictation. The `Preserve Clipboard` menu toggle is the escape hatch for sensitive workflows.

* No status-bar pulse, system sound, or other feedback when activation fails or the target is gone — clipboard is the universal safety net.

* No system-shortcut conflict warning (e.g., picking `Cmd+Space` as the hotkey is allowed without a warning).

* No XCTest suite migration — verification stays manual end-to-end, matching the existing project posture.

### Deferred to Follow-Up Work

* Visual recording overlay (small on-screen indicator while recording): deferred to a later phase.

* n8n / Jarvis command-mode hotkey: Phase 3 candidate.

* Meeting recorder (ScreenCaptureKit + AVAudioEngine): Phase 3 candidate.

* Custom dictionary / forced capitalizations: deferred.

* Auto language switch (PT / EN per phrase): deferred.

* Notification-driven activation (replacing fixed `pasteDelayMs` with `NSWorkspace.didActivateApplicationNotification` observation): future iteration if 500ms default proves insufficient in practice.

* Window-level / text-field-level focus lock: out of scope; v1 is app-level only.

***

## Context & Research

### Relevant Code and Patterns

* `Sources/OpenWisprLib/AppDelegate.swift` — recording lifecycle (`handleRecordingStart`, `handleRecordingStop`), `applyConfigChange`. The Whisper completion block on the main queue (`DispatchQueue.main.async` after `transcriber.transcribe`) is where activation + delayed paste hooks in.

* `Sources/OpenWisprLib/TextInserter.swift` — current `insert(text:)` saves pasteboard, sets text, posts `Cmd+V` via `CGEvent`, restores pasteboard 100ms later. New work: parameterize the restore step and add an empty-text guard.

* `Sources/OpenWisprLib/Config.swift` — additive optional fields with defaults. Pattern already in use for `startSound` / `startSoundEnabled` etc. (Phase 1). `effectiveMaxRecordings` is the existing clamping pattern to mirror for `pasteDelayMs`.

* `Sources/OpenWisprLib/StatusBarController.swift` — submenu pattern at `langSubmenu` (\~line 134), `modelSubmenu` (\~line 170), `audioSubmenu` (\~line 233). `Toggle Mode` checkmark item is the pattern for the two new toggles. The existing `state` enum (with a `.recording` case set by AppDelegate via `statusBar.state = .recording`) is the source of truth for "am I currently recording" — no new callback needed.

* `Sources/OpenWisprLib/HotkeyManager.swift` — `start` / `stop` for pause-during-capture. Modifier-only key whitelist at `isModifierOnlyKey` already covers codes 54–63; extending to include `57` (Caps Lock) is in scope.

* `Sources/OpenWisprLib/KeyCodes.swift` — `parse` accepts `"cmd+shift+r"` style input; `describe` produces the inverse for menu labels.

* `Sources/OpenWispr/main.swift` line 37 — `NSApp.setActivationPolicy(.accessory)`. The app is a menu-bar agent. This is the constraint that drives the NSPanel configuration in U6.

### Institutional Learnings

* No `docs/solutions/` directory in this repo — institutional learnings carried via `CHANGELOG.md` and `CLAUDE.md`. Phase 1 entry (2026-04-22) captures the brew-binary-swap + ad-hoc codesign + TCC re-grant procedure that applies to this phase too.

### External References

* `NSWorkspace.shared.frontmostApplication` returns `NSRunningApplication?`; instance retains across the Whisper window. `isTerminated` reflects death.

* `NSRunningApplication.activate(options: .activateIgnoringOtherApps)` is supported on `.macOS(.v13)` (the Package.swift target). It may silently no-op on macOS 14+ under tightened focus-stealing rules — verify activation took effect by re-reading `NSWorkspace.shared.frontmostApplication?.processIdentifier` after the paste delay.

* `DistributedNotificationCenter.default()` — public path for screen-lock observation. Notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` fire reliably on lock state changes. Replaces the private `CGSSessionCopyCurrentDictionary` SPI considered earlier.

* `NSPanel` configuration for an `.accessory` app: `.borderless` plus `.nonactivatingPanel` style mask is **mandatory** (not optional). The panel must override `canBecomeKey` to return `true`. Before `makeKeyAndOrderFront(nil)`, call `NSApp.activate(ignoringOtherApps: true)` so key events route to the panel's local monitor.

* `NSEvent.addLocalMonitorForEvents(matching:handler:)` is the local-only counterpart of the global monitor `HotkeyManager` already uses; events from the panel itself flow through this rather than the global tap. Returns `nil` from the handler to consume the event.

* `ProcessInfo.processInfo.processIdentifier` is always available; comparing against `frontmost.processIdentifier` is the robust way to detect "the snapshot is open-wispr itself" without relying on `Bundle.main.bundleIdentifier` (which can be `nil` for SwiftPM executables run inside a brew-installed `.app` bundle).

***

## Key Technical Decisions

* **Single** **`focusLockEnabled`** **boolean** (default true) instead of a three-mode enum. Rationale: user collapsed the original `auto/clipboard/off` design into a single behavior — always try focus, always leave on clipboard. A boolean is the smallest correct shape.

* **Snapshot stored on** **`AppDelegate.pendingFocusTarget`** **ivar at start, captured by value into the Whisper completion closure inside** **`handleRecordingStop`.** The ivar is the bridge between two separate methods (`handleRecordingStart` and `handleRecordingStop`); the closure capture is what gives each in-flight transcription its own target reference even across overlapping recordings. Each new start-press overwrites the ivar; the previous transcription still has its captured value.

* **Per-recording config snapshot.** When the Whisper completion closure is built, capture `focusLockEnabled` and `preserveClipboard` into the closure alongside the target. Toggling the menu items mid-Whisper affects the *next* recording, never the in-flight one.

* **Cross-recording activate() guard.** `activate()` is a global side-effect — bringing app A forward while recording B is in progress would steal focus from B. Inside the completion closure, before calling `activate()`, check `isPressed`: if a new recording is in progress, skip activation entirely and go straight to paste-into-frontmost + clipboard.

* **Filter open-wispr from snapshot targets via** **`processIdentifier`** **comparison** (`ProcessInfo.processInfo.processIdentifier`), not `Bundle.main.bundleIdentifier`. The bundle ID approach fails for SwiftPM executables installed via brew (no `Info.plist` in the executable target).

* **Skip activation + paste when screen is locked.** Maintain a `screenLocked: Bool` ivar on `AppDelegate` updated by `DistributedNotificationCenter` observers for `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`. Public API; replaces the private `CGSSessionCopyCurrentDictionary` SPI in earlier drafts.

* **Verify activation after the paste delay.** After `activate()` and the `pasteDelayMs` wait, re-read `NSWorkspace.shared.frontmostApplication?.processIdentifier`. If it does not match the snapshot, log + still call `inserter.insert` (paste lands in current frontmost; clipboard is the safety net). Defends against macOS 14+ silent activation no-op.

* **`pasteDelayMs`** **is config-driven, default 500, clamped 0–5000ms** in an `effectivePasteDelayMs` helper that mirrors `effectiveMaxRecordings`. Rationale: 500ms is a more defensible floor for cross-Space activation, cold-launched Electron apps (Slack, VS Code), and fresh-window cases (iTerm new tabs). Tunable for users who want it shorter without recompile.

* **`TextInserter.insert(text:restoreClipboard:)`** **parameterized**, with empty-text guard inside the function. Single semantic direction throughout: `restoreClipboard: true` matches the user-facing `preserveClipboard: true` config — both mean "put the prior pasteboard back". Avoids the inverse-naming confusion of an earlier draft.

* **`HotkeyManager`** **paused while the capture panel is open** via new `AppDelegate.pauseHotkey()` / `resumeHotkey()` methods that wrap `hotkeyManager?.stop()` and re-create. Resume is wired to BOTH `windowWillClose` and `windowDidResignKey` notifications, plus a 5-second no-input watchdog timer. Belt-and-suspenders against a panel that loses key without firing close.

* **Hotkey menu items disabled while** **`state == .recording`** rather than allowing mid-recording rebind. Read `if case .recording = self.state` directly inside `StatusBarController.buildMenu()`. The existing `state` enum is the source of truth — no new callback channel needed (drops a layer the earlier draft proposed).

* **Two menu toggles in addition to JSON config**, mirroring `Toggle Mode`. Rationale: \~3 lines per toggle, gives the user a one-click escape hatch if either feature misbehaves in real use. The `Preserve Clipboard` toggle is also the escape hatch for sensitive-content workflows (R3).

* **Caps Lock allowed as a hotkey.** Extend `HotkeyManager.isModifierOnlyKey` whitelist to include keycode 57.

* **No XCTest suite added.** Rationale: matches existing project posture; verification is manual after brew binary swap, as in Phase 1.

***

## Open Questions

### Resolved During Planning

* *How should the clipboard regression risk (Universal Clipboard sync, clipboard managers logging dictations, sensitive-content overwrite) be mitigated?* Resolved: `preserveClipboard` config field + menu toggle (default off). Honors the user's stated "always clipboard" intent while providing an opt-out. Documented as an explicit Risk so users know to enable it when handling sensitive content.

* *What happens to the focus target when a second recording starts before the first's Whisper finishes?* Resolved: snapshot is stored on `pendingFocusTarget` ivar at start-press, captured by value into the Whisper completion closure inside `handleRecordingStop`. Each in-flight transcription owns its target. Cross-recording activate() race is guarded explicitly (skip activation if `isPressed == true` at completion time).

* *What happens when* *`frontmostApplication`* *is open-wispr itself?* Resolved: filtered out via `processIdentifier` comparison (robust against the SwiftPM `Bundle.main.bundleIdentifier == nil` case in brew installs); falls back to default behavior (paste into whatever is frontmost at paste time, plus clipboard).

* *Is* *`CGSSessionCopyCurrentDictionary`* *safe to depend on?* Resolved: replaced with public `DistributedNotificationCenter` observation of `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`. No private SPI dependency.

* *What's the right paste delay default?* Resolved: 500ms (raised from earlier 200ms draft) covers cross-Space activation, cold-launched Electron apps, and fresh-window cases.

* *How should Caps Lock be handled in the capture panel?* Resolved: allowed; extend `isModifierOnlyKey` whitelist to keycode 57.

### Deferred to Implementation

* Whether 500ms `pasteDelayMs` is sufficient across the full app matrix the user actually dictates into. Empirical question; the user can raise the value via the config file or the `Preserve Clipboard` toggle is the safety net. If 500ms proves widely wrong, future iteration could replace fixed delay with notification-driven activation (`NSWorkspace.didActivateApplicationNotification`).

* Whether activation-verification logging (the post-delay frontmost re-check) should produce a status-bar feedback or stay silent. Default: silent — matches Scope decision on no fallback feedback.

***

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
record-start press
  │
  ▼
handleRecordingStart()
  │ snapshot = NSWorkspace.shared.frontmostApplication
  │ if snapshot.processIdentifier == ProcessInfo.processInfo.processIdentifier:
  │     snapshot = nil
  │ self.pendingFocusTarget = snapshot
  │ recorder.startRecording()
  │ play start sound
  │
  ▼
[recording in progress — user may switch apps freely]
  │
  ▼
record-stop press / toggle release
  │
  ▼
handleRecordingStop()
  │ recorder.stopRecording()
  │ play end sound
  │ // Capture state into Whisper completion closure:
  │ let target = self.pendingFocusTarget
  │ let focusLock = config.focusLockEnabled?.value ?? true
  │ let preserve = config.preserveClipboard?.value ?? false
  │ async { whisper.transcribe(audio) → text }
  │
  ▼
[transcription complete on main queue]
  │
  ▼
if text.isEmpty || error: idle (no clipboard mutation)
  │
  ▼
if focusLock && target != nil && !target.isTerminated && !screenLocked && !isPressed:
  │   target.activate(options: .activateIgnoringOtherApps)
  │   wait pasteDelayMs (500ms default)
  │   if NSWorkspace.frontmost.processIdentifier != target.processIdentifier:
  │       log "activation failed silently"
  │       (still proceed to paste — clipboard has text either way)
  │
  ▼
inserter.insert(text: text, restoreClipboard: preserve)
  │   guard !text.isEmpty (defensive)
  │   save pasteboard
  │   clear, set text
  │   simulate Cmd+V
  │   if restoreClipboard: restore saved pasteboard 100ms later
  │   else: leave transcribed text on clipboard
  │
  ▼
state: idle
```

```
Hotkey UI:
  StatusBarController.buildMenu()
    └── Hotkey: <current>  ▶ (greyed if state == .recording)
          ├── Right Option       ✓
          ├── Right Cmd
          ├── F13
          ├── Cmd+Shift+R
          ├── ─────
          └── Custom…  →  HotkeyCaptureWindow
                            ├── pauseHotkey() on open
                            ├── NSPanel: .borderless + .nonactivatingPanel
                            │            canBecomeKey override returns true
                            │            NSApp.activate(ignoringOtherApps:) before show
                            ├── local monitor: keyDown / flagsChanged
                            ├── states: waiting (empty placeholder)
                            │           partial (modifier held → live "⌥" preview)
                            │           committed (instant close)
                            ├── Esc / Cmd+Q / resignKey / 5s watchdog → cancel
                            ├── valid capture → KeyCodes.parse → Config.save → applyConfigChange
                            └── resumeHotkey() on windowWillClose AND windowDidResignKey
```

Final menu layout post-Phase-2 (top-down):

```
OpenWispr v0.35.0
Ready (hotkey: <current>)
─────
Language: <current>           ▶
Model: <current>              ▶
Audio Input: <current>        ▶
Hotkey: <current>             ▶
─────
✓ Toggle Mode
✓ Focus Lock
  Preserve Clipboard
─────
Copy Last Dictation         ⌘C
─────
Reload Configuration         ⌘R
Open Configuration           ⌘O
─────
Quit                          ⌘Q
```

***

## Implementation Units

* U1. **Add config fields and clamping**

**Goal:** Introduce `focusLockEnabled`, `pasteDelayMs`, and `preserveClipboard` config fields with sensible defaults and clamping for the delay.

**Requirements:** R2, R3, R9.

**Dependencies:** None.

**Files:**

* Modify: `Sources/OpenWisprLib/Config.swift`

**Approach:**

* Add three new optional fields: `focusLockEnabled: FlexBool?`, `pasteDelayMs: Int?`, `preserveClipboard: FlexBool?`.

* Update `defaultConfig` to set `focusLockEnabled = FlexBool(true)`, `pasteDelayMs = 500`, `preserveClipboard = FlexBool(false)`.

* Add an `effectivePasteDelayMs(_:)` helper mirroring the existing `effectiveMaxRecordings` shape: `nil` → 500, otherwise clamp to `[0, 5000]`.

**Patterns to follow:**

* Existing Phase 1 sound config additions (`startSound`, `startSoundEnabled`) for nullable + default pattern.

* `effectiveMaxRecordings` (Config.swift) for clamping helper.

**Test scenarios:**

* *Happy path.* Existing config file lacking the three new fields decodes successfully; `Config.load()` returns defaults for them.

* *Edge case.* `pasteDelayMs: 999999` resolves to `5000` via the helper.

* *Edge case.* `pasteDelayMs: -50` resolves to `0` via the helper.

* *Happy path.* JSON written with the new fields decodes back to identical values (round-trip).

**Verification:**

* Existing user config at `~/.config/open-wispr/config.json` loads without error after the change.

* A fresh install writes a `config.json` containing the three new fields with their defaults.

***

* U2. **Parameterize TextInserter with restoreClipboard + empty-text guard**

**Goal:** Allow callers to choose whether to restore the pre-recording pasteboard or leave the transcribed text on the clipboard, with a defensive empty-text guard inside the function itself.

**Requirements:** R3, R5.

**Dependencies:** None.

**Files:**

* Modify: `Sources/OpenWisprLib/TextInserter.swift`

**Approach:**

* Change `insert(text:)` to `insert(text:restoreClipboard:)`. The parameter direction matches the user-facing `preserveClipboard` config (both `true` mean "put the prior pasteboard back"). When `false` (the default), skip the restore step — the transcribed text remains on the clipboard.

* Add `guard !text.isEmpty else { return }` at the top of the function. Defensive against future call sites that might invoke `insert` without a caller-side empty check.

* The pasteboard save step still runs in both modes (cheap, defensive — preserves the option to revert if needed).

**Patterns to follow:**

* Existing `restorePasteboard` / `savePasteboard` private helpers stay unchanged.

**Test scenarios:**

* *Happy path.* `restoreClipboard: true` → after a manual paste, the prior clipboard contents are restored within \~100ms.

* *Happy path.* `restoreClipboard: false` → after paste, the transcribed text is the current clipboard content (verifiable via Cmd+V into a second app).

* *Edge case.* Empty `text` argument: function returns immediately, no pasteboard mutation, no Cmd+V posted.

* *Edge case.* Both modes still post a valid `Cmd+V` event (paste actually happens in the active app).

**Verification:**

* Cmd+V in a second app after a dictation in `restoreClipboard: false` mode pastes the dictation text.

* Dictation in `restoreClipboard: true` mode preserves whatever was on the clipboard before the dictation.

***

* U3. **Wire focus-lock into the recording lifecycle**

**Goal:** Snapshot at start, activate + delay + verify + paste at end, race-safe across overlapping recordings, defensive against locked screen, dead targets, and silent activation failures.

**Requirements:** R1, R2, R4, R5.

**Dependencies:** U1, U2.

**Files:**

* Modify: `Sources/OpenWisprLib/AppDelegate.swift`

**Approach:**

* Add stored properties on `AppDelegate`: `pendingFocusTarget: NSRunningApplication?`, `screenLocked: Bool`. Wire `screenLocked` to `DistributedNotificationCenter.default()` observers for `com.apple.screenIsLocked` (set true) and `com.apple.screenIsUnlocked` (set false), set up during `setupInner`.

* In `handleRecordingStart`: capture `NSWorkspace.shared.frontmostApplication` immediately (before `recorder.startRecording`). If `snapshot?.processIdentifier == ProcessInfo.processInfo.processIdentifier`, treat as no snapshot. Assign to `self.pendingFocusTarget`. (Each new start-press overwrites the ivar; previous closures still hold their captured copies.)

* In `handleRecordingStop` (before dispatching the Whisper transcribe block): capture state into locals — `let target = self.pendingFocusTarget`, `let focusLock = config.focusLockEnabled?.value ?? true`, `let preserve = config.preserveClipboard?.value ?? false`. These locals are captured by the completion closure; toggling menu items mid-Whisper does not affect the in-flight recording.

* Inside the Whisper completion block on the main queue:

  * Empty / error transcription: do not call `inserter.insert` at all. Clipboard untouched (matches existing behavior plus R5).

  * Otherwise: branch on `focusLock`.

    * If `focusLock`, `target != nil`, `!target.isTerminated`, `!screenLocked`, AND `!isPressed` (no overlapping recording in progress): call `target.activate(options: .activateIgnoringOtherApps)`, then `DispatchQueue.main.asyncAfter(deadline: .now() + delay)` with `delay = TimeInterval(Config.effectivePasteDelayMs(config.pasteDelayMs)) / 1000`. After the delay, verify `NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier`; if mismatch, log `"focus-lock: activation no-op"` and proceed anyway. Then call `inserter.insert(text:, restoreClipboard: preserve)`.

    * Otherwise (focus-lock disabled, target gone, screen locked, or overlapping recording): skip activation, call `inserter.insert(text:, restoreClipboard: preserve)` directly. Paste lands in current frontmost; clipboard has text either way.

**Patterns to follow:**

* Existing `DispatchQueue.main.asyncAfter` usage in `handleRecordingStop` (5-second error-state reset).

* Existing closure-captured `self`/`recorder` pattern in `handleRecordingStop`.

**Test scenarios:**

* *Happy path.* Record in TextEdit, switch to Safari during Whisper, paste lands in TextEdit (TextEdit becomes frontmost, paste in TextEdit).

* *Happy path.* Record in TextEdit, do not switch apps, paste lands in TextEdit normally (no visible activate flicker).

* *Edge case.* Record in an app, quit that app during Whisper, transcription finishes: clipboard contains text, no crash, no spurious paste in another app.

* *Edge case.* Record in an app, lock the screen during Whisper: transcription finishes, clipboard contains text, no activate or paste fires.

* *Edge case.* Record in an app, screensaver / fast-user-switch during Whisper: same as lock — `screenLocked` flips via the distributed notification, paste skipped.

* *Edge case.* Record while open-wispr's own UI is frontmost (panel open then dismissed without clicking elsewhere): snapshot is filtered via processIdentifier, paste lands in whatever is now frontmost, clipboard contains text.

* *Edge case.* Toggle mode: start recording A, start recording B before A's Whisper completes. A's Whisper completion sees `isPressed == true` (B is recording), skips activate, pastes into B's current frontmost + clipboard. B's completion (if it fires while A's pasteDelayMs is still pending) handles its own target normally.

* *Edge case.* Activation succeeds visibly but `processIdentifier` mismatch after delay (silent no-op on macOS 14+): log line emitted, paste fires anyway into current frontmost, clipboard has text.

* *Error path.* Whisper transcribe throws: clipboard untouched, idle state restored.

* *Error path.* Empty / silent transcription: clipboard untouched, idle state restored.

* *Integration.* `focusLockEnabled = false` in config: activation skipped, paste happens normally into whatever is frontmost; `preserveClipboard` flag still respected independently.

* *Integration.* User toggles `Focus Lock` off in the menu while Whisper is processing: in-flight recording uses the value captured at start (still does focus-lock); next recording uses the new value.

**Verification:**

* The cross-app dictation flow works end-to-end: start in app A, switch to B during Whisper, transcribed text appears in A.

* No crashes with screen lock, screensaver, or app quit during Whisper across 5 manual repetitions each.

* Overlap test (toggle mode, two rapid recordings) does not produce cross-contamination.

***

* U4. **Menu toggles for Focus Lock and Preserve Clipboard**

**Goal:** Two new checkmark menu items, each toggling the corresponding config field. Final menu layout specified.

**Requirements:** R9.

**Dependencies:** U1, U3.

**Files:**

* Modify: `Sources/OpenWisprLib/StatusBarController.swift`

**Approach:**

* In `buildMenu`, after the existing `Toggle Mode` item, add `Focus Lock` and `Preserve Clipboard` items as `NSMenuItem`s with `state = .on` or `.off` based on `config.focusLockEnabled?.value ?? true` and `config.preserveClipboard?.value ?? false`.

* Each item's action toggles the field, calls `cfg.save()` (matching the existing `Toggle Mode` action shape), and triggers `onConfigChange?(cfg)`.

* Final menu layout (replicates the High-Level Technical Design diagram): header → status line → separator → Language ▶ / Model ▶ / Audio Input ▶ / Hotkey ▶ → separator → ✓ Toggle Mode / ✓ Focus Lock / Preserve Clipboard → separator → Copy Last Dictation → separator → Reload Configuration / Open Configuration → separator → Quit.

**Patterns to follow:**

* Existing `Toggle Mode` menu item construction and action wiring.

**Test scenarios:**

* *Happy path.* Click `Focus Lock` → checkmark toggles, `~/.config/open-wispr/config.json` reflects the new value, dictation behavior changes accordingly on the next recording.

* *Happy path.* Click `Preserve Clipboard` → checkmark toggles, dictation now restores prior clipboard contents on the next recording.

* *Integration.* Restart the app: both toggles reflect the persisted state.

* *Integration.* Menu order matches the specified layout post-Phase-2.

**Verification:**

* Both toggles round-trip through the config file and produce the expected behavior on the next recording.

* Visual menu layout matches the spec.

***

* U5. **Hotkey submenu with locked preset list**

**Goal:** Submenu listing common hotkey presets plus a `Custom…` entry, mirroring existing submenus. Preset list is fixed; checkmark resolution is verified to round-trip through `KeyCodes.parse` / `KeyCodes.describe`.

**Requirements:** R6, R10.

**Dependencies:** U1.

**Files:**

* Modify: `Sources/OpenWisprLib/StatusBarController.swift`

**Approach:**

* Build `hotkeySubmenu` mirroring the `langSubmenu` / `modelSubmenu` / `audioSubmenu` shape. Top-level `Hotkey: <current describe>` item with the submenu attached.

* Locked preset list: `Right Option` (= `"rightoption"`), `Right Cmd` (= `"rightcmd"`), `F13` (= `"f13"`), `Cmd+Shift+R` (= `"cmd+shift+r"`). Each preset's action calls `KeyCodes.parse(presetString)`, sets `config.hotkey`, saves, fires `onConfigChange`.

* Show a checkmark on the preset matching the current `config.hotkey` (compare by `keyCode` + sorted `modifiers` after parsing the preset string). Verify during implementation that `KeyCodes.parse` of each preset string round-trips: parsing produces a `(keyCode, modifiers)` whose `keyCode` matches `config.hotkey.keyCode` exactly when the preset is the current bind, and the description via `KeyCodes.describe(keyCode, modifiers)` produces a consistent label for menu display.

* Disable the submenu and parent item via `if case .recording = self.state` check inside `buildMenu` (no new callback channel — uses existing `state` enum). Set `isEnabled = false` and `autoenablesItems = false` on the submenu when recording.

* `Custom…` is the last item, separated. Action: open the capture window (U6).

**Patterns to follow:**

* `langSubmenu` construction and click-to-set-config pattern (\~line 134).

* `autoenablesItems = false` pattern from `audioSubmenu`.

**Test scenarios:**

* *Happy path.* Click each preset → hotkey rebinds, `config.json` updates, the recording hotkey fires correctly on the next press.

* *Happy path.* Submenu shows a checkmark on the currently active preset.

* *Edge case.* While recording (toggle mode `state == .recording`), the submenu items and the parent item are disabled (greyed in the UI).

* *Edge case.* If the current hotkey doesn't match any preset (e.g., the user used `Custom…` previously), no preset is checked, and the parent label shows the current bind string via `KeyCodes.describe`.

* *Integration.* For each preset string, verify `KeyCodes.parse(preset)` round-trips: parsing produces a `(keyCode, modifiers)` tuple that, when compared against an equivalently-set `config.hotkey`, matches by `keyCode` + sorted `modifiers`.

**Verification:**

* Each preset binds correctly across at least one full restart of the app.

* Greying respects toggle-mode active-recording state.

* Checkmark appears on the right preset when config matches.

***

* U6. **Hotkey-capture panel (new file)**

**Goal:** Borderless `NSPanel` configured for an `.accessory` app that captures the next key or modifier-only key and persists it as the new hotkey, with multiple cancellation paths and explicit UI states.

**Requirements:** R7, R8.

**Dependencies:** U1, U5, U7.

**Files:**

* Create: `Sources/OpenWisprLib/HotkeyCaptureWindow.swift`

* Modify: `Sources/OpenWisprLib/StatusBarController.swift` (the `Custom…` action wires here)

**Approach:**

* `HotkeyCaptureWindow`: an `NSPanel` subclass (or controller wrapping one) with these mandatory settings for an `.accessory` app:

  * Style mask: `.borderless` plus `.nonactivatingPanel` (mandatory — without it, key events do not reach the panel from a menu-bar-only app).

  * Override `canBecomeKey` to return `true`.

  * Level: `.floating`. Centered on the active screen.

  * Before `makeKeyAndOrderFront(nil)`, call `NSApp.activate(ignoringOtherApps: true)` so key events route to the panel's local monitor.

* Three UI states with explicit visual feedback:

  * **Waiting** — empty placeholder under a "Press a key…" label. No combo shown.

  * **Partial** — modifier held but no terminal key yet. Show a live preview of the held modifiers (`⌥`, `⇧⌘`, etc.) so the user sees the state transition.

  * **Committed** — capture succeeded. Close immediately (no confirmation flash — fast feedback, avoids a "did it crash?" feel).

* On `makeKeyAndOrderFront`: install `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])` returning `nil` (consumes events from the panel) so events do not bubble. Also set up a `Timer.scheduledTimer` for 5 seconds that auto-cancels the panel if no input arrives.

* Capture rules:

  * `keyDown` with a printable / functional key → build `"<modifier>+<modifier>+<key>"` from `event.modifierFlags` and `event.keyCode` (lookup via `KeyCodes.codeToName`), call `KeyCodes.parse`, save and close on success.

  * `flagsChanged` for a modifier-only key (codes 54–63 plus 57 for Caps Lock — extend `HotkeyManager.isModifierOnlyKey` whitelist) → on the *down* edge, capture as the new hotkey, save, close.

  * Escape (keyCode 53) → cancel (close without saving).

  * `Cmd+Q` (keyCode 12 with `.command`) → cancel (intercepted by the local monitor, never reaches `NSApp.terminate`).

  * Watchdog timer expires (5s no input) → cancel, close.

* On open: call `AppDelegate.pauseHotkey()` (U7).

* On close (any path including resignKey / watchdog / capture / Esc / Cmd+Q): call `AppDelegate.resumeHotkey()` (U7). Wire the resume call into BOTH `windowWillClose` AND `windowDidResignKey` so a panel that loses key without closing still resumes the global hotkey.

* Save flow: `KeyCodes.parse(captured) → HotkeyConfig` → set `config.hotkey` → `config.save()` → `onConfigChange?(config)`.

**Patterns to follow:**

* `HotkeyManager`'s modifier-only-vs-regular-key dispatch logic for capture-side parity.

**Test scenarios:**

* *Happy path.* Open panel via `Custom…`, press `Right Option` → panel closes, hotkey rebinds to `rightoption`, next recording fires correctly.

* *Happy path.* Press `Cmd+Shift+R` → captured as `cmd+shift+r`, parses, saves.

* *Happy path.* Hold `⌥` (Right Option) for 1 second before release → during the hold, "Partial" state shows live `⌥` preview; on commit, panel closes.

* *Edge case.* Press Caps Lock (keyCode 57) → captured as `capslock` (whitelist extended).

* *Edge case.* Press Escape → cancels, panel closes, no rebind.

* *Edge case.* Press `Cmd+Q` while panel is open → cancels, app does not quit.

* *Edge case.* Click outside the panel (resignKey) → cancels, hotkey resumes.

* *Edge case.* Open panel and walk away — after 5 seconds, watchdog auto-cancels and resumes hotkey.

* *Edge case.* Click menu bar icon while panel is open: panel resigns key (no `windowWillClose`), the `windowDidResignKey` path still fires `resumeHotkey()` — global hotkey is restored even though the panel might still be visible.

* *Integration.* Press the *current* recording hotkey while panel is open → captured as the new bind, no recording starts (because U7 paused the global monitor).

* *Edge case.* Press a dead key (e.g., `Option+E` on US layout) → captured by virtual key code; displayed name is whatever `KeyCodes.codeToName` returns for that code (acceptable; not blocked).

**Verification:**

* Each capture path (preset key, modifier-only, combo, Esc cancel, `Cmd+Q` cancel, resign-key cancel, watchdog cancel) works once across a manual run.

* The global hotkey listener is fully restored after the panel closes (next recording works normally) — regardless of the close path.

***

* U7. **AppDelegate pause/resume + isPressed-aware menu (minimal plumbing)**

**Goal:** Glue the capture panel to `HotkeyManager` (pause / resume around capture). The menu greying piece uses the existing `state` enum directly — no new callback channel is added.

**Requirements:** R8, R10.

**Dependencies:** U3, U5, U6.

**Files:**

* Modify: `Sources/OpenWisprLib/AppDelegate.swift`

**Approach:**

* On `AppDelegate`: add `pauseHotkey()` (calls `hotkeyManager?.stop()`, sets a `hotkeyPaused = true` flag) and `resumeHotkey()` (rebuilds and starts the hotkey manager from current config, sets `hotkeyPaused = false`). The capture panel calls these on open / close (U6 wires the resume to both `windowWillClose` and `windowDidResignKey` plus the watchdog).

* Menu greying: handled directly in `StatusBarController.buildMenu` (U5) by reading `if case .recording = self.state`. No new callback or property on AppDelegate is needed.

**Patterns to follow:**

* Existing `hotkeyManager?.stop()` / re-create + `start` pattern in `applyConfigChange`.

**Test scenarios:**

* *Happy path.* Open capture panel → pressing the current hotkey does nothing (recording does not start). Close panel → hotkey resumes, next press triggers recording.

* *Edge case.* Toggle mode, start recording, attempt to open `Custom…` → menu items are greyed via `state == .recording`.

* *Edge case.* Open panel, dismiss via Esc, immediately press the current hotkey → recording starts normally (no leaked paused state).

* *Edge case.* Open panel, click menu bar icon, panel loses key but doesn't close → `windowDidResignKey` fires `resumeHotkey()` — global hotkey works again.

* *Integration.* Open panel, rebind, close. Next press of new hotkey → recording starts. Old hotkey no longer triggers.

**Verification:**

* The Hotkey submenu greys out during a toggle-mode recording.

* Pause / resume around the capture panel produces no stuck-paused state across at least 5 open / close cycles, including the resignKey-without-close and watchdog paths.

***

## System-Wide Impact

* **Interaction graph:** `AppDelegate` ↔ `StatusBarController` (existing `onConfigChange`, plus `state` enum read by StatusBarController). `StatusBarController` ↔ `HotkeyCaptureWindow` (open / close). `AppDelegate` ↔ `HotkeyManager` (existing start / stop, plus pause / resume around capture). `AppDelegate` ↔ `TextInserter` (existing single call site, signature now passes `restoreClipboard`). `AppDelegate` ↔ `DistributedNotificationCenter` (new screen-lock observers).

* **Error propagation:** Activation failure — both terminated targets and silent macOS-14+ no-ops — falls through to "paste into current frontmost"; clipboard always has the text. Screen-lock skips activation entirely. Whisper errors / empty transcription leave the clipboard untouched.

* **State lifecycle risks:** `pendingFocusTarget` ivar is overwritten on each new start-press; in-flight transcriptions hold their own captured copies via the closure. `hotkeyPaused` flag must be cleared in all panel-close paths — covered by wiring resume to BOTH `windowWillClose` AND `windowDidResignKey`, plus the 5s watchdog. `screenLocked` ivar lifecycle matches the `DistributedNotificationCenter` observer registration (set up in `setupInner`).

* **API surface parity:** Three new optional config fields (additive, JSON-decoder safe). One `TextInserter.insert` signature change (single call site updated). New public methods on `AppDelegate` (`pauseHotkey`, `resumeHotkey`). New public type `HotkeyCaptureWindow`.

* **Integration coverage:** Cross-Space activation, hotkey rebind during active recording (blocked by greying via `state` enum), overlapping recordings (target captured per-closure + cross-recording activate guard), and panel-resignKey-without-close (covered by dual notification wiring) all require manual end-to-end coverage — not provable by unit tests alone.

* **Cross-recording side-effect note:** `activate()` is a global side-effect. Recording B receiving focus from recording A's completion is the failure mode; the explicit `if !isPressed` guard inside the completion closure mitigates it.

* **Unchanged invariants:** Existing language / model / audio device flows untouched. `Toggle Mode`, press-and-hold mode, start / end sounds, and recording-store pruning all preserved as-is. Existing config files load without migration.

***

## Risks & Dependencies

| Risk                                                                                                                                                                                                  | Mitigation                                                                                                                                                                                                          |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 500ms `pasteDelayMs` insufficient for some apps (e.g., Slack cold-launch, multi-second VS Code initialization).                                                                                       | Tunable via config; user can raise to 1000-2000ms. Future iteration may replace fixed delay with `NSWorkspace.didActivateApplicationNotification` observation.                                                      |
| `TextInserter.insert` signature change is breaking.                                                                                                                                                   | Only one call site exists (`AppDelegate.handleRecordingStop`); update in same unit (U3).                                                                                                                            |
| `NSPanel` `resignKey` behavior differs across macOS versions for borderless / non-activating panels in `.accessory` apps.                                                                             | Mandatory `.nonactivatingPanel` style mask + `canBecomeKey` override + `NSApp.activate(ignoringOtherApps:)` before show. Resume-hotkey wired to both `windowWillClose` and `windowDidResignKey` plus a 5s watchdog. |
| `NSRunningApplication.activate(options:)` is deprecated on macOS 14+ and may silently no-op.                                                                                                          | Post-delay verification: re-read `NSWorkspace.shared.frontmostApplication?.processIdentifier`. On mismatch, log + paste anyway (clipboard is the safety net).                                                       |
| `hotkeyPaused` flag leak if panel loses key without closing.                                                                                                                                          | Resume wired to `windowDidResignKey` notification in addition to `windowWillClose`, plus a 5s no-input watchdog timer.                                                                                              |
| `Bundle.main.bundleIdentifier` returns `nil` for SwiftPM executables run inside a brew-installed `.app` bundle, breaking the "snapshot is open-wispr itself" filter.                                  | Use `processIdentifier` comparison (`ProcessInfo.processInfo.processIdentifier`) instead — always available.                                                                                                        |
| **Sensitive previously-copied content is silently overwritten** when `preserveClipboard: false` (the default). Passwords, account numbers, MFA codes from a prior copy are replaced by the dictation. | Documented as an explicit Risk + Scope Boundary. The `Preserve Clipboard` menu toggle is the per-session escape hatch. README/CHANGELOG note this trade-off explicitly.                                             |
| Cross-recording activate() race in toggle mode (A's completion brings A's target forward while B is recording).                                                                                       | Explicit guard inside the Whisper completion closure: if `isPressed == true` (B is recording), skip activate, paste into current frontmost + clipboard.                                                             |
| User binds `Cmd+V` as the recording hotkey — `simulatePaste` could re-trigger the global monitor.                                                                                                     | Acknowledged risk; not blocked. The global monitor is a passive observer, not a consumer; the user opting into this binding accepts the recursion. Documented in CHANGELOG.                                         |
| Private-SPI dependency on `CGSSessionCopyCurrentDictionary` for screen-lock detection (earlier draft).                                                                                                | Replaced with public `DistributedNotificationCenter` observation of `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`. No SPI surface.                                                                      |

***

## Documentation / Operational Notes

* `README.md` — add `Focus Lock` and `Hotkey submenu` to the feature list. Include a one-paragraph note about the `Preserve Clipboard` toggle and the sensitive-content trade-off so users know the escape hatch exists.

* `CHANGELOG.md` — Phase 2 entry on completion (per global rule). Include the pasteable rollback snippet matching the Phase 1 entry's shape. Call out the clipboard-overwrite trade-off explicitly so the next reader of the changelog understands why `Preserve Clipboard` exists.

* Manual verification checklist — derive from the test scenarios across U1–U7. Run end-to-end against the dev binary before the brew bundle swap. Specifically include: cross-Space test, target-app-quit test, screen-lock test, screensaver test, overlapping-recordings test, panel-resignKey-without-close test, sensitive-clipboard regression test (verify the toggle works as the escape hatch).

* Brew binary swap (post-verification) — same procedure as Phase 1: `brew services stop`, copy binary into `/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/`, ad-hoc codesign (`codesign --force --sign -`), `brew services start`, re-grant Accessibility in System Settings (the new ad-hoc signature is treated as a new app by TCC).

***

## Sources & References

* `CHANGELOG.md` — Phase 1 audio feedback (2026-04-22), planning notes for focus-lock / hotkey UI / meeting recorder (2026-04-29).

* `CLAUDE.md` — project standing brief, Phase 2 candidate descriptions and open-question history.

* `Sources/OpenWisprLib/AppDelegate.swift` — recording lifecycle and config-change wiring.

* `Sources/OpenWisprLib/StatusBarController.swift` — submenu pattern (`langSubmenu`, `modelSubmenu`, `audioSubmenu`), `Toggle Mode` checkmark item, and the `state` enum used for menu-greying.

* `Sources/OpenWisprLib/TextInserter.swift` — pasteboard save / restore + `Cmd+V` simulation.

* `Sources/OpenWisprLib/HotkeyManager.swift` — global event monitor, modifier-only key whitelist (codes 54–63; extended to 57 for Caps Lock in U6).

* `Sources/OpenWisprLib/KeyCodes.swift` — `parse` and `describe` helpers; round-trip verification done in U5.

* `Sources/OpenWisprLib/Config.swift` — `FlexBool`, `effectiveMaxRecordings` clamping pattern.

* `Sources/OpenWispr/main.swift:37` — `NSApp.setActivationPolicy(.accessory)` is the constraint that drives the NSPanel configuration in U6.
