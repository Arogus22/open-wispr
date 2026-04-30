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

The user (Rafael) uses open-wispr daily for dictation. Adds quality-of-life features missing upstream:
- Phase 1: audio feedback (sounds on record start/stop)
- Phase 2: focus-lock (paste lands in original app even after switching during Whisper) + in-app hotkey-capture UI

## Current status (as of 2026-04-30)

### Phases shipped

- ✅ **Phase 1 (2026-04-22):** Audio feedback. Ping on start, Bottle on stop. Config-driven, toggleable per side. In daily use.
- ✅ **Phase 2 (2026-04-30):** Focus-lock + Hotkey UI bundled. Branch `feat/phase-2-focus-lock-hotkey-ui` pushed to fork. 9 commits. In daily use.

### Build & ship pipeline

**Canonical release flow: `./scripts/ship.sh`** (one command does it all):
```
swift build → brew services stop → backup binary → install → codesign --deep --sign "OpenWispr Local Build" → brew services start
```
~10s end-to-end. Backups go to `/opt/homebrew/Cellar/open-wispr/0.35.0/_backups/` (NOT inside the bundle — that breaks `--deep` codesign).

### Code-signing identity (load-bearing)

The build pipeline depends on a self-signed cert called **`OpenWispr Local Build`** in the user's login keychain, with trust setting `codeSign` → `trustRoot`.

**Why it matters:** TCC keys the Accessibility grant to the cert's identity (stable across builds), not the binary hash (changes every build). This is what allows `./scripts/ship.sh` to install a new build without forcing the user to re-grant Accessibility every time.

**If the cert is missing** (e.g., fresh machine, keychain lost, user re-imported clean), `ship.sh` fails at the `codesign` step with "no identity found". Recovery: see `docs/INSTALL.md` for the one-time `openssl` + `security` setup procedure.

### Relauncher shortcut

`/Applications/OpenWispr.command` (custom icon, hidden extension — appears as `OpenWispr` in Finder/Spotlight) is a bash one-liner that runs `brew services restart open-wispr`. Findable via Cmd+Space → "OpenWispr" → Enter. Use case: user did Quit from menu bar and wants to relaunch without Terminal.

### Installed binary state

The brew bundle at `/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/` contains the cert-signed Phase 2 build. Originals backed up in `_backups/`:
- `open-wispr.app-bin.<TS>` and `open-wispr.cli-bin.<TS>` — pre-Phase-2 ad-hoc swap
- `open-wispr.bak.20260422_184624` — original Phase 1 swap
- `open-wispr.bak.20260430_2023` — pre-cert ad-hoc Phase 2 swap

**A future `brew upgrade open-wispr` or `brew reinstall open-wispr` will overwrite these.** Recovery: re-run `./scripts/ship.sh`.

## Next up — feature roadmap

### Phase 3+ (deferred, not committed)

- **n8n / Jarvis integration.** Second "command mode" hotkey that POSTs Whisper output to an n8n webhook instead of pasting. Local Whisper replaces paid cloud STT. Open: which hotkey, webhook URL config, auth/shared-secret, response feedback UX.
- **Meeting recorder.** ScreenCaptureKit (system audio) + AVAudioEngine (mic) → dual-stream transcription with speaker labels → transcript file. New "meeting mode". ~3–4 days.
- **Custom dictionary.** Force specific capitalizations and spellings (e.g., `n8n`, `Evolução Exponencial`). Post-Whisper substitution pass.
- **Visual overlay.** Discreet recording indicator in screen corner.
- **Auto language switch EN/PT.** May not be needed if Whisper's `auto` mode handles it — needs investigation.
- **PR upstream to `human37/open-wispr`.** Phase 2 features are general-purpose; ship.sh + cert pipeline is fork-specific. Would need to simplify before proposing.

### Explicitly dropped

- **Real-time / live transcription.** Whisper isn't truly streaming; sliding-window and VAD-chunked approaches both sacrifice accuracy and add CPU cost. Accuracy chosen over latency on 2026-04-29.

## Constraints and preferences (from user's global rules)

- **Never implement without explicit permission.** Discuss plan, wait for "go ahead", then act.
- **Batch questions** into one numbered list — don't drip them.
- **Root cause, not symptoms.** If a build fails, understand why before patching around it.
- **Simplicity first.** Smallest clean solution. No overengineering.
- **Verification before done.** After any code change, actually run the app and confirm it works. Don't claim success from a clean compile alone.
- **Session changelog mandatory** (outside GSD workflow). Append a dated entry to `CHANGELOG.md` at session end.

## User context (short)

- Portuguese-speaking. Responds in Portuguese. Strategic thinker — wants to align on plan before execution.
- Comfortable with Claude Code, GSD, MCP. Mac ARM (1TB).
- Runs an AI automation business ("Evolução Exponencial") — this tool is for personal dictation workflow, not a client deliverable.

## What NOT to do

- **Don't run `brew upgrade open-wispr` or `brew reinstall open-wispr`** during the project — overwrites all custom work.
- **Don't put backups inside `Contents/MacOS/`** — breaks `codesign --deep`. Use `_backups/` at the bundle's parent.
- **Don't sign with `--sign -` (ad-hoc)** when `scripts/ship.sh` exists. The cert pipeline is the canonical path.
- **Don't commit `.gitnexus/`, `AGENTS.md`, or `.claude/skills/gitnexus/`** — these are GitNexus pollution. The tool has no Swift parser; not used in this project.
- **Don't reintroduce the machine-default `Rafael Ramos <arogus@...>` identity in commits.** Git is configured globally to use `Arogus <Arogus22@users.noreply.github.com>`.

## Resolved questions (historical)

1. ~~Fork-first or clone-then-decide?~~ → Forked: `Arogus22/open-wispr`.
2. ~~Which default sounds?~~ → Ping (start) / Bottle (end) — matches the pt_PT "Sonar" / "Seixo".
3. ~~Install method?~~ → brew. Patched binary in Cellar `.app` bundle.
4. ~~Two sounds or three (incl. transcription-done)?~~ → Two for Phase 1.
5. ~~Phase 2 design: 3-mode `targetLockMode` or single boolean?~~ → Single `focusLockEnabled` boolean (user collapsed the design to one behavior: always try focus + always clipboard).
6. ~~Where do backups live?~~ → `_backups/` directory at the bundle's parent. NOT inside `Contents/MacOS/`.
7. ~~Ad-hoc or self-signed cert?~~ → Self-signed (`OpenWispr Local Build`). TCC grant survives rebuilds.
8. ~~How does user relaunch after Quit?~~ → `/Applications/OpenWispr.command` (Spotlight findable, custom icon). Or `brew services restart open-wispr` in Terminal.
9. ~~GitNexus for code intelligence?~~ → No. No Swift parser; only indexed Ruby + markdown for this codebase.
