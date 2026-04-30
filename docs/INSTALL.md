# Building from source — Fork install guide

> This guide is for **contributors and people maintaining a fork**. End users should use [`docs/install-guide.md`](install-guide.md) (the upstream-style installer).
>
> If you cloned this fork and want to ship a custom build to your own Mac with a stable Accessibility grant across rebuilds, this is the guide for you.

## Table of contents

1. [Prerequisites](#prerequisites)
2. [One-time setup — self-signed cert](#one-time-setup--self-signed-cert)
3. [Installing the fork](#installing-the-fork)
4. [Daily workflow — `./scripts/ship.sh`](#daily-workflow--scriptsshipsh)
5. [Quality-of-life — relauncher shortcut](#quality-of-life--relauncher-shortcut)
6. [How brew daemon and `.command` shortcut interact](#how-brew-daemon-and-command-shortcut-interact)
7. [Troubleshooting](#troubleshooting)
8. [Rollback](#rollback)
9. [Why this exists — design rationale](#why-this-exists--design-rationale)

---

## Prerequisites

**Required**

- macOS 13 (Ventura) or later — `Package.swift` targets `.macOS(.v13)`
- **Xcode Command Line Tools** — provides `swift`, `codesign`, `sips`, `Rez`, `DeRez`, `SetFile`. Install: `xcode-select --install`
- **Homebrew** — required for `brew services`, the runtime daemon manager. Install: see [brew.sh](https://brew.sh)
- **`whisper-cpp`** — `brew install whisper-cpp`. Required runtime dependency for transcription.

**Optional**

- **Node.js** — only if you want to use `npx`-based developer tools (e.g., GitNexus for code intelligence on JS/TS/Python projects). Not used by `ship.sh`.

---

## One-time setup — self-signed cert

Without this, the Accessibility grant will reset on every rebuild (TCC keys ad-hoc signatures by binary hash, which changes each build). The cert provides a stable identity so the grant persists.

**Estimated time:** 10 minutes (mostly waiting for `openssl`).

### 1. Generate a self-signed code-signing certificate

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/openwispr-key.pem -out /tmp/openwispr-cert.pem \
  -sha256 -days 3650 -nodes \
  -subj "/CN=OpenWispr Local Build" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature"
```

This creates a 2048-bit RSA key + X.509 cert with `extendedKeyUsage=codeSigning`. 10 years validity. Subject is **`OpenWispr Local Build`** — `scripts/ship.sh` looks up this exact name, so don't change it without also updating the script.

### 2. Convert to PKCS#12 (Keychain-importable)

```bash
openssl pkcs12 -export -out /tmp/openwispr.p12 \
  -inkey /tmp/openwispr-key.pem \
  -in /tmp/openwispr-cert.pem \
  -password pass:openwispr-temp-import \
  -name "OpenWispr Local Build"
```

The password `openwispr-temp-import` is only used during the import — the cert lands in your keychain unencrypted (per macOS keychain policy).

### 3. Import to login keychain with codesign access

```bash
security import /tmp/openwispr.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P openwispr-temp-import \
  -T /usr/bin/codesign \
  -A
```

- `-T /usr/bin/codesign` — explicitly grants `codesign` access to use the private key
- `-A` — allow all apps to use the key without prompting (one-time setup; safer than entering a password every signing operation)

### 4. Add trust setting for code signing

This step **will prompt for your macOS admin password** (it's writing to the keychain trust policy). One-time.

```bash
security find-certificate -c "OpenWispr Local Build" -p ~/Library/Keychains/login.keychain-db > /tmp/openwispr-cert-export.cer

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db \
  -p codeSign \
  /tmp/openwispr-cert-export.cer
```

### 5. Verify the cert is usable

```bash
security find-identity -v -p codesigning | grep "OpenWispr Local Build"
```

You should see one line like:
```
1) <40-hex-chars> "OpenWispr Local Build"
```

If you see "0 valid identities found", trust didn't take — re-run step 4 and check for password prompt cancellation.

### 6. Cleanup

```bash
rm -f /tmp/openwispr-key.pem /tmp/openwispr-cert.pem /tmp/openwispr-cert-export.cer /tmp/openwispr.p12
```

The cert + key are now in your keychain. The temp files are no longer needed.

---

## Installing the fork

Clone, build, and swap into a brew-installed bundle.

### 1. Clone

```bash
git clone https://github.com/Arogus22/open-wispr.git
cd open-wispr
```

(Or your own fork's URL.)

### 2. Make sure brew has open-wispr installed

```bash
brew install open-wispr
```

This installs the upstream version into `/opt/homebrew/Cellar/open-wispr/0.35.0/`. We're going to swap our custom build into that bundle.

> **Why:** brew sets up a launchctl agent (`~/Library/LaunchAgents/homebrew.mxcl.open-wispr.plist`) that auto-starts the daemon at login. Reusing this infrastructure is simpler than running a parallel `.app`.

### 3. First swap with `./scripts/ship.sh`

```bash
./scripts/ship.sh
```

This builds, swaps, and signs. See the next section for what it does step by step.

### 4. Grant Accessibility — last time you'll do this

Open **System Settings → Privacy & Security → Accessibility** and add:

```
/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app
```

Toggle ON. The daemon should detect the grant within ~1 second and start working.

> **Future rebuilds via `ship.sh` will preserve this grant** because the cert identity is stable. This is the whole point of the cert setup.

---

## Daily workflow — `./scripts/ship.sh`

After making source changes:

```bash
./scripts/ship.sh
```

What it does (in order):

1. **`swift build -c release`** — produces `.build/release/open-wispr`. Aborts on build failure with the last 20 lines of build log.
2. **`brew services stop open-wispr`** + `launchctl bootout` — cleanly stops the daemon. Bootout cleans launchd state to avoid "Bootstrap failed: 5: I/O error" on the next start.
3. **Backup** — copies the current installed binary to `/opt/homebrew/Cellar/open-wispr/0.35.0/_backups/` with a timestamped suffix. **Backups go OUTSIDE the bundle** — putting them inside `Contents/MacOS/` would pollute the codesign manifest.
4. **Install** — copies `.build/release/open-wispr` into both:
   - `/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr` (the GUI/menu-bar app)
   - `/opt/homebrew/Cellar/open-wispr/0.35.0/bin/open-wispr` (the CLI)
5. **Codesign** — `codesign --force --deep --sign "OpenWispr Local Build" /path/to/OpenWispr.app` (and the CLI separately, non-deep).
6. **`brew services start open-wispr`** — restart the daemon via launchctl.

Total time: ~10 seconds for a typical rebuild.

If everything is wired correctly:
- The daemon starts.
- The menu-bar icon appears within 2-3 seconds.
- **No Accessibility prompt** (cert identity unchanged → grant preserved).
- The hotkey works immediately.

If you DO get an Accessibility prompt: the cert may have been rotated, or the trust setting was lost. Re-grant manually this time, then verify the cert is intact.

---

## Quality-of-life — relauncher shortcut

If you Quit the daemon manually (via the menu-bar icon's **Quit** item), launchd does not auto-restart. To bring it back without opening Terminal:

### Option A — `.command` file in `/Applications`

Create a clickable bash launcher:

```bash
cat > "/Applications/OpenWispr.command" <<'EOF'
#!/bin/bash
brew services restart open-wispr
echo "Restarting open-wispr brew service..."
sleep 2
EOF
chmod +x "/Applications/OpenWispr.command"
```

Then double-click in Finder, or Cmd+Space → type "OpenWispr" → Enter. Terminal opens for ~2s, runs the command, daemon restarts. The menu-bar icon reappears.

> **Why this works for ad-hoc/self-signed apps when Spotlight launching the `.app` doesn't:** `.command` files are launched via Terminal.app, which is a Gatekeeper-approved system app. The Terminal-launched script invokes `brew services restart`, which goes through `launchctl`, which bypasses Gatekeeper entirely.

### Option B — Custom icon for the `.command`

If you want the `.command` to look like the actual app in Finder/Spotlight (purple icon, no `.command` extension visible):

```bash
ICON_SRC="/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/Resources/AppIcon.icns"
TARGET="/Applications/OpenWispr.command"
TMP_ICON="/tmp/openwispr-icon.icns"
TMP_RSRC="/tmp/openwispr-icon.rsrc"

# 1. Add icon resource to the .icns itself
cp "$ICON_SRC" "$TMP_ICON"
sips -i "$TMP_ICON"

# 2. Extract the icon resource as .rsrc
DeRez -only icns "$TMP_ICON" > "$TMP_RSRC"

# 3. Append to the .command's resource fork
Rez -append "$TMP_RSRC" -o "$TARGET"

# 4. Mark "has custom icon" + hide the extension
SetFile -a CE "$TARGET"

# 5. Refresh Finder cache
killall Finder

# 6. Cleanup
rm -f "$TMP_ICON" "$TMP_RSRC"
```

After this, the file appears in Finder as `OpenWispr` with the proper icon. Spotlight indexes it the same way.

---

## How brew daemon and `.command` shortcut interact

There are two paths for the daemon to be running:

| Path | When |
|---|---|
| **Brew LaunchAgent** (`~/Library/LaunchAgents/homebrew.mxcl.open-wispr.plist`) | Auto-loads at user login. Always active unless you `brew services stop`. |
| **`OpenWispr.command` shortcut** | Manual relaunch after Quit. Runs `brew services restart`, which kills any current daemon and starts a new one. |

**Don't put `OpenWispr.command` as a Login Item.** It's redundant with the brew LaunchAgent (which already auto-starts at login) and produces a brief icon flicker — daemon starts → Login Item runs → daemon kills + restarts → new icon. Not destructive but wasteful.

**Don't run two daemons simultaneously.** If you Quit via the menu-bar icon AND start one via Terminal `brew services start`, you'll get one running daemon. If you somehow start two (e.g., directly executing the binary while the brew daemon runs), they'll fight over the global hotkey monitor.

---

## Troubleshooting

### "Accessibility: not granted" loop

The daemon hangs at startup waiting for Accessibility. Likely causes:

1. **First swap** — you haven't granted yet. Open System Settings, add the bundle path, toggle ON.
2. **TCC stale entry** — toggle ON in System Settings but daemon still says "not granted". The TCC entry is keyed to an old signature.
   ```bash
   tccutil reset Accessibility com.human37.open-wispr
   ```
   Then re-add via System Settings (toggle should now apply correctly).
3. **Cert drift** — you re-imported the cert (different public-key hash). Same as case 2; re-grant fixes it.

### `codesign` fails: "no identity found"

```
errSecCSCMSSignerNotFound
```

The cert is missing or its trust setting was lost. Verify:

```bash
security find-identity -v -p codesigning | grep "OpenWispr Local Build"
```

If empty, re-do the [self-signed cert setup](#one-time-setup--self-signed-cert) (steps 4-5 are the most likely to have failed silently).

### `brew services start` fails: "Bootstrap failed: 5: Input/output error"

A previous daemon crashed and left a stale launchd registration:

```bash
launchctl bootout gui/$(id -u)/homebrew.mxcl.open-wispr
brew services start open-wispr
```

`bootout` cleans the registration so `start` can bootstrap fresh.

### Spotlight / Finder won't open `OpenWispr.app` (the actual `.app`, not the `.command`)

Expected behavior — Gatekeeper rejects ad-hoc/self-signed `.app` bundles via LaunchServices. Use the `.command` shortcut instead, or `brew services restart open-wispr` in Terminal.

### `codesign --deep` says "invalid resource directory"

The bundle has files inside `Contents/MacOS/` that don't belong (typically `.bak` files from earlier swaps).

```bash
ls /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/
# Should only show: open-wispr (and nothing else)
```

If there are `.bak` files inside, move them out:

```bash
mkdir -p /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/
mv /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/*.bak.* \
   /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/
```

Then re-run `./scripts/ship.sh`.

### GitNexus warning in your Claude/Cursor session

If you see "GitNexus index is stale (last indexed: never)" in tool reminders: GitNexus has no Swift parser — analyzing this project produces a near-empty index. Either ignore the reminder (zero cost) or disable the hook globally. **Do not** commit `.gitnexus/`, `AGENTS.md`, or `.claude/skills/gitnexus/` if they appear after running `npx gitnexus analyze` — these are pollution. Revert with:

```bash
git checkout CLAUDE.md
rm -f AGENTS.md
find .claude/skills/gitnexus -type f -delete 2>/dev/null
find .claude/skills/gitnexus -depth -type d -empty -delete 2>/dev/null
npx gitnexus clean --force
```

---

## Rollback

If something is broken and you need to revert to a known-good state.

### Roll back to the last `ship.sh` build

```bash
brew services stop open-wispr
launchctl bootout gui/$(id -u)/homebrew.mxcl.open-wispr 2>/dev/null
LATEST=$(ls -t /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/open-wispr.app-bin.* | head -1)
cp "$LATEST" /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr
codesign --force --deep --sign "OpenWispr Local Build" \
  /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app
brew services start open-wispr
```

### Roll back to the original Phase 1 binary

```bash
brew services stop open-wispr
launchctl bootout gui/$(id -u)/homebrew.mxcl.open-wispr 2>/dev/null
cp /opt/homebrew/Cellar/open-wispr/0.35.0/_backups/open-wispr.bak.20260422_184624 \
   /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app/Contents/MacOS/open-wispr
codesign --force --deep --sign "OpenWispr Local Build" \
  /opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app
brew services start open-wispr
```

### Roll back to upstream (no fork mods)

```bash
brew services stop open-wispr
brew reinstall open-wispr
brew services start open-wispr
```

This restores the upstream-installed binary. You'll lose the fork's features but everything works again.

---

## Why this exists — design rationale

### Why not just use ad-hoc signing?

Ad-hoc (`codesign --sign -`) produces a binary with no signing identity — TCC treats every build as a fresh app. Every rebuild forces the user back to System Settings → Privacy & Security → Accessibility to re-toggle the grant. This is intolerable for active development.

### Why self-signed cert instead of Apple Developer cert?

Apple Developer certs cost $99/year and are managed via Apple's developer portal. A self-signed cert costs nothing and is generated locally. The trade-offs:

- ❌ Self-signed apps still trigger Gatekeeper warnings via Spotlight/Finder. The `.command` shortcut workaround eliminates this for normal use.
- ✅ TCC grants persist across rebuilds (the only thing that mattered for daily-use friction).
- ✅ Local-only — no cloud account, no expiration headaches.

For a single-user personal fork, this is the right trade-off.

### Why backup outside the bundle?

`codesign --deep` recomputes the bundle's `_CodeSignature/CodeResources` manifest by hashing every file under `Contents/`. If you put `.bak` files in `Contents/MacOS/`, they get included in the manifest. Future signature verification then includes them too — but if you ever delete a `.bak` file, the verification fails ("invalid resource directory").

Solution: backups live in a sibling `_backups/` directory, never inside `Contents/`.

### Why a `.command` instead of the `.app` directly?

Gatekeeper's `spctl` rejects self-signed apps when launched via LaunchServices (Spotlight, Finder, `open` command). It accepts them when launched via `launchctl` (which is how `brew services` works under the hood) — `launchctl` is treated as a system-level mechanism that bypasses Gatekeeper.

The `.command` file is launched by Terminal.app (Gatekeeper-approved), which then runs `brew services restart` (which uses `launchctl`). Two layers of bypass. Plus you can give it a custom icon and hide the extension, so it looks like a normal app launcher.

---

## Submitting changes upstream

If you've made a change you'd like to PR back to [`human37/open-wispr`](https://github.com/human37/open-wispr):

1. Make sure your changes don't depend on the cert pipeline (upstream uses ad-hoc).
2. Branch: `git checkout -b feat/<your-feature>`
3. Push to your fork: `git push -u origin feat/<your-feature>`
4. Open PR via GitHub UI: `https://github.com/Arogus22/open-wispr/pull/new/feat/<your-feature>` (or your fork's equivalent), and target `human37/open-wispr:main`.

Phase 2's focus-lock and hotkey UI are general-purpose and would be candidates. The cert pipeline + `ship.sh` is fork-maintenance infrastructure and is NOT appropriate to upstream.
