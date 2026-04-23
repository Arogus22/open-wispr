# CLAUDE.md — open-wispr fork project

Standing context for any Claude Code session opened in this directory. Read first.

## What this project is

A personal fork/modification of **open-wispr**, an open-source speech-to-text app for macOS.

- **Upstream repo:** `https://github.com/human37/open-wispr`
- **Language:** Swift (native macOS app)
- **License:** MIT (permissive — can modify, redistribute, fork freely)
- **Install method on user's machine:** likely via `brew` (verify before touching installed binary)

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

## Prerequisites the user needs

- **Xcode Command Line Tools** — user confirmed NOT installed at project start. Command: `xcode-select --install` (opens macOS installer popup, ~3GB). MUST be installed before any `swift build` can run.
- **Swift toolchain** — comes with Command Line Tools on macOS.
- **GitHub fork decision** — not yet made. Options:
  - Clone original → patch → build → (maybe) PR. Simpler if feature makes it upstream.
  - Fork on GitHub first → clone fork → patch → push to fork → (maybe) PR. Better if user wants a long-lived personal version.

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

## Open questions to resolve early

1. Fork-first on GitHub, or clone-then-decide?
2. Which default sounds does the user want (Tink/Pop/Glass/other)?
3. Is open-wispr installed via `brew`, downloaded binary, or built from source previously? (affects where the replacement binary goes)
4. Does the user want three separate sounds (start/end/transcription-done) or just two (start/end) for Phase 1?
