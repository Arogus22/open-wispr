#!/bin/bash
# Ship a fresh build of open-wispr into the brew-installed location.
#
# Usage:
#   ./scripts/ship.sh
#
# What it does:
#   1. swift build -c release
#   2. brew services stop open-wispr
#   3. Backup current binary to <brew>/_backups/ with timestamp
#   4. Copy new binary into the brew bundle
#   5. codesign --force --deep --sign "<IDENTITY>" the bundle
#   6. brew services start open-wispr
#
# Why the cert (vs ad-hoc):
#   The Accessibility (TCC) grant is keyed to the code-signing identity, not
#   the binary hash. As long as every build uses the same cert, the grant
#   survives across rebuilds. Ad-hoc signing breaks the grant on every
#   rebuild because the hash changes.
#
# Prerequisites (one-time setup, already done in this repo):
#   - Self-signed cert "OpenWispr Local Build" exists in the login keychain
#   - The cert has trust policy `codeSign` set to trustRoot
#   - The cert has been used to sign the current installed bundle once
#   - The user has granted Accessibility to the bundle once
#
# If you ever need to rebuild the cert:
#   See docs/plans/2026-04-29-001-feat-phase-2-focus-lock-hotkey-ui-plan.md
#   for the openssl + security commands used to create it.

set -e

CERT_IDENTITY="OpenWispr Local Build"
APP="/opt/homebrew/Cellar/open-wispr/0.35.0/OpenWispr.app"
APP_BIN="$APP/Contents/MacOS/open-wispr"
CLI_BIN="/opt/homebrew/Cellar/open-wispr/0.35.0/bin/open-wispr"
BACKUP_DIR="/opt/homebrew/Cellar/open-wispr/0.35.0/_backups"
DEV_BIN="$(pwd)/.build/release/open-wispr"

echo "=== ship.sh — open-wispr release build + install ==="
echo ""

# Sanity check: cert is in the keychain
if ! security find-identity -v -p codesigning | grep -q "$CERT_IDENTITY"; then
    echo "ERROR: Code signing identity not found: $CERT_IDENTITY"
    echo "Either the cert is missing or its trust setting is not configured."
    echo "See the script header for the one-time setup procedure."
    exit 1
fi

# Sanity check: brew bundle exists where we expect
if [ ! -d "$APP" ]; then
    echo "ERROR: Brew bundle not found at $APP"
    echo "Has open-wispr been installed via brew? (brew install open-wispr)"
    exit 1
fi

echo "[1/6] Building release..."
swift build -c release > /tmp/openwispr-build.log 2>&1 || {
    echo "ERROR: swift build failed. See /tmp/openwispr-build.log"
    tail -20 /tmp/openwispr-build.log
    exit 1
}
echo "      ✓ build complete"

if [ ! -x "$DEV_BIN" ]; then
    echo "ERROR: dev binary not produced at $DEV_BIN"
    exit 1
fi

echo "[2/6] Stopping brew service..."
brew services stop open-wispr > /dev/null 2>&1 || true
launchctl bootout gui/501/homebrew.mxcl.open-wispr 2>/dev/null || true
sleep 1
echo "      ✓ stopped"

echo "[3/6] Backing up current binaries..."
mkdir -p "$BACKUP_DIR"
TS=$(date +%Y%m%d_%H%M%S)
cp "$APP_BIN" "$BACKUP_DIR/open-wispr.app-bin.$TS"
cp "$CLI_BIN" "$BACKUP_DIR/open-wispr.cli-bin.$TS"
echo "      ✓ backups saved to $BACKUP_DIR (suffix .$TS)"

echo "[4/6] Installing new binary..."
cp "$DEV_BIN" "$APP_BIN"
cp "$DEV_BIN" "$CLI_BIN"
echo "      ✓ installed"

echo "[5/6] Code-signing bundle with $CERT_IDENTITY..."
codesign --force --deep --sign "$CERT_IDENTITY" "$APP" > /dev/null 2>&1 || {
    echo "ERROR: codesign failed"
    exit 1
}
codesign --force --sign "$CERT_IDENTITY" "$CLI_BIN" > /dev/null 2>&1 || {
    echo "ERROR: codesign of CLI binary failed"
    exit 1
}
echo "      ✓ signed"

echo "[6/6] Starting brew service..."
brew services start open-wispr > /dev/null 2>&1
sleep 2
PID=$(pgrep -f "open-wispr start" | head -1)
if [ -n "$PID" ]; then
    echo "      ✓ daemon started (PID $PID)"
else
    echo "      ⚠ daemon may not have started — check 'brew services list'"
fi

echo ""
echo "=== Done. ==="
echo ""
echo "Accessibility grant is preserved across builds (cert identity unchanged)."
echo "If the menu bar icon shows a lock and the hotkey doesn't respond:"
echo "  1. The cert may have been rotated — re-grant in System Settings."
echo "  2. Check 'tccutil reset Accessibility com.human37.open-wispr' if needed."
echo ""
echo "To rollback: copy the latest backup from $BACKUP_DIR back into place"
echo "and 'brew services restart open-wispr'."
