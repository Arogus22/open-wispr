# CLAUDE.md — open-wispr fork project

Standing context for any Claude Code session opened in this directory. Read first.

## What this project is

A personal fork/modification of **open-wispr**, an open-source speech-to-text app for macOS.

- **Upstream repo:** `https://github.com/human37/open-wispr`
- **User's fork (origin):** `https://github.com/Arogus22/open-wispr`
- **Language:** Swift 6.3 (native macOS app, SwiftPM)
- **License:** MIT (permissive — can modify, redistribute, fork freely)
- **Install method on user's machine:** `brew install open-wispr` (binary at `/opt/homebrew/Cellar/open-wispr/0.35.0/`, managed as a brew service).

## Why this fork exists

The user (Rafael) uses open-wispr daily for dictation. The upstream app has **no audio feedback** — you don't know when recording started/stopped without looking at the screen. This project adds that, plus potentially other quality-of-life features.

## Goals (scope of this fork)

### Phase 1 — Audio feedback (primary goal)
- Play a sound when recording **starts**
- Play a sound when recording **ends**
- Optionally: a third sound when **transcription is done** (after Whisper finishes processing)
- Sounds should be:
  - Configurable via JSON config (`startSound`, `endSound`, `transcriptionDoneSound`)
  - Pickable from macOS system sounds (`Tink`, `Pop`, `Glass`, `Ping`, etc.) or custom file path
  - Toggleable (each one independently on/off)
- Implementation hint: `NSSound(named:)` or `AudioServicesPlaySystemSound` — whichever fits the existing codebase style

### Phase 2 — Nice-to-haves (only after Phase 1 works end-to-end)
- **Custom dictionary** — force specific capitalizations/spellings (e.g. "n8n" stays "n8n", "Evolução Exponencial" always capitalized)
- **Minimal visual overlay** — small discreet indicator in screen corner while recording
- **Auto language switch** — detect PT vs EN per phrase and pick the right Whisper model

Do NOT start Phase 2 until Phase 1 is compiled, installed, and confirmed working in real use.

## Working plan

1. **Clone** — `git clone https://github.com/human37/open-wispr.git .` (into this directory). Decide fork-first-or-later with user.
2. **Explore** — map the codebase. Where is recording start/stop triggered? Where is the config loaded? What's the build system (SwiftPM? Xcode project?)?
3. **Plan the patch** — present a concrete file-by-file diff plan to the user before editing anything.
4. **Implement Phase 1** — smallest viable change first (one hardcoded beep on start), then generalize to config-driven.
5. **Build** — `swift build -c release` (or the project's actual build command).
6. **Test** — run the modified binary, confirm beeps fire at the right moments.
7. **Install** — replace the brew-installed binary (or wherever it lives) with the compiled one. Back up the original first.
8. **(Optional) PR upstream** — if the feature is clean, open a Pull Request to `human37/open-wispr`. Elegant path: user benefits, everyone benefits, no permanent fork to maintain.

## Current status (as of 2026-04-24)

- **Phase 1 shipped and in daily use.** Sounds fire on start (Ping / "Sonar") and stop (Bottle / "Seixo"). Config lives at `~/.config/open-wispr/config.json`.
- **Build toolchain ready.** Xcode Command Line Tools installed. `swift build -c release` works from this directory.
- **Fork set up.** Pushed to `Arogus22/open-wispr` on `main`. Git identity is privacy-safe: `Arogus <Arogus22@users.noreply.github.com>` (GitHub noreply alias — no real name in commits). Initial commit's author was rewritten; do NOT reintroduce the machine-default `Rafael Ramos <arogus@...>` identity.
- **Installed binary is patched.** The brew `.app` bundle contains the custom build. Originals backed up as `*.bak.20260422_184624` alongside. A future `brew upgrade open-wispr` or `brew reinstall open-wispr` will overwrite these — rebuild + re-swap + re-codesign + re-grant Accessibility if that happens (see 2026-04-22 CHANGELOG entry for the exact commands).

## Next up — feature roadmap (as of 2026-04-29)

Active feature threads in dependency-aware order. Do NOT implement any of these until the open questions are answered and the user gives explicit go-ahead.

### Phase 2 candidates (small, ready to plan + implement)

- **Focus-lock (paste target + clipboard fallback).** Today, if the user starts a recording in app A, switches to app B during recording, and presses stop, the transcription pastes into app B. Plan: snapshot `NSWorkspace.shared.frontmostApplication` at record start; after Whisper completes (NOT at stop press), re-activate snapshot app, wait ~300ms, then paste. Config: `targetLockMode` ∈ {`"auto"` (default), `"clipboard"`, `"off"`} and `pasteDelayMs` (default 300). Clipboard fallback when target app is gone. **Critical timing:** activation must be post-transcription, not at stop-press, otherwise the 4–5s Whisper wait kills the "browse during processing" workflow. ~1 day scope.
- **Hotkey-capture UI.** Add Hotkey submenu (preset list + "Custom…") to the menu bar. "Custom…" opens borderless `NSPanel` capturing the next key or modifier-only key (via `flagsChanged`), saves via existing `KeyCodes.parse` → `Config.save` flow. ~½ day scope.

**Open questions before starting Phase 2:**
1. `targetLockMode` default = `"auto"` — confirm?
2. Lock target = frontmost at *start* press (not stop) — confirm?
3. Fallback feedback (activation failure / clipboard mode): status bar only, distinct sound, or both?
4. `pasteDelayMs` default = 300ms — OK?
5. Bundle hotkey-UI with focus-lock as one commit, or separate Phase 2.5?

### Phase 3+ (larger, deferred)

- **n8n / Jarvis integration.** Second "command mode" hotkey that POSTs Whisper output to an n8n webhook instead of pasting. Key win: local Whisper replaces paid cloud STT. Open design questions: which hotkey, webhook URL config location, auth/shared-secret, response feedback UX. Not implementation-ready.
- **Meeting recorder.** Capture system audio (ScreenCaptureKit) + mic, transcribe both streams, output to transcript file with speaker labels. New "meeting mode" trigger. ~3–4 days. Discussed 2026-04-29, not committed.
- **Custom dictionary, visual overlay, auto language switch** — Phase 2 ideas from earlier roadmap. Still on deck, deprioritized below focus-lock + hotkey UI.

### Explicitly dropped

- **Real-time / live transcription.** Whisper isn't truly streaming; sliding-window and VAD-chunked approaches both sacrifice accuracy and add CPU cost. User chose accuracy over latency on 2026-04-29.

## Constraints and preferences (from user's global rules)

- **Never implement without explicit permission.** Discuss plan, wait for "go ahead", then act.
- **Batch questions** into one numbered list — don't drip them.
- **Root cause, not symptoms.** If a build fails, understand why before patching around it.
- **Simplicity first.** Smallest clean solution. No overengineering.
- **Verification before done.** After any code change, actually run the app and confirm the beep fires. Don't claim success from a clean compile alone.
- **Session changelog mandatory** (outside GSD workflow). Append a dated entry to `CHANGELOG.md` at session end summarizing what changed, why, which files were touched, and any external changes (installed binaries replaced, brew state modified, etc.).

## User context (short)

- Portuguese-speaking. Responds in Portuguese. Strategic thinker — wants to align on plan before execution.
- Comfortable with Claude Code, GSD, MCP. Mac ARM (1TB).
- Runs an AI automation business ("Evolução Exponencial") — this tool is for his personal dictation workflow, not a client deliverable.

## What NOT to do

- Don't touch the user's installed open-wispr binary until the new build has been tested and the original is backed up.
- Don't run `brew upgrade open-wispr` during the project — it would overwrite any local changes.
- Don't start on Phase 2 features before Phase 1 is working in real use.
- Don't assume the build system — inspect the repo (`Package.swift`? `.xcodeproj`? both?) before running any build command.

## Resolved questions (historical)

1. ~~Fork-first or clone-then-decide?~~ → Forked: `Arogus22/open-wispr`.
2. ~~Which default sounds?~~ → Ping (start) / Bottle (end) — matches the pt_PT "Sonar" / "Seixo" the user asked for.
3. ~~Install method?~~ → brew. Patched binary sits in the Cellar `.app` bundle.
4. ~~Two sounds or three (incl. transcription-done)?~~ → Two for Phase 1. Transcription-done can come later if useful.
