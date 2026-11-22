#!/bin/bash
# Installs the DEBUG simulator build and launches it signed in with an API key (read-only: the app blocks changes).
# Usage: scripts/sim-run.sh <visionos|tvos|ios> [tab] [route] [search]   e.g. scripts/sim-run.sh tvos explore title/movie/350
# Needs HOLYARRS_SERVER and either HOLYARRS_API_KEY or HOLYARRS_KEYCHAIN_SERVICE (+ _ACCOUNT) for the key.
# Optional: JF_TOKEN + JF_USER (+ JELLYFIN_SERVER) for Jellyfin rows and playback, PLAY=<seconds>, ASK=1.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
DEV="$(sim_udid "$1")"; APP="$(app_path "$1")"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
KEY="${HOLYARRS_API_KEY:-$(security find-generic-password -s "${HOLYARRS_KEYCHAIN_SERVICE:-}" -a "${HOLYARRS_KEYCHAIN_ACCOUNT:-$USER}" -w)}"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null || true
SIMCTL_CHILD_HOLYARRS_SERVER="$HOLYARRS_SERVER" SIMCTL_CHILD_HOLYARRS_API_KEY="$KEY" \
SIMCTL_CHILD_HOLYARRS_TAB="${2:-home}" SIMCTL_CHILD_HOLYARRS_OPEN="${3:-}" SIMCTL_CHILD_HOLYARRS_QUERY="${4:-}" \
SIMCTL_CHILD_HOLYARRS_ASK="${ASK:-}" SIMCTL_CHILD_HOLYARRS_PLAY="${PLAY:-}" \
SIMCTL_CHILD_HOLYARRS_JF_TOKEN="${JF_TOKEN:-}" SIMCTL_CHILD_HOLYARRS_JF_USER="${JF_USER:-}" SIMCTL_CHILD_HOLYARRS_JF_SERVER="${JELLYFIN_SERVER:-}" \
  xcrun simctl launch "$DEV" "$BUNDLE" >/dev/null
echo "launched on $DEV"
