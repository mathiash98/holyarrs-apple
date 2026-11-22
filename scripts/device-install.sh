#!/bin/bash
# Builds Release for a paired Apple Vision Pro, Apple TV, iPhone or iPad and installs it.
# Usage: scripts/device-install.sh <device-udid> [--no-install]
# Signing uses your team from Config/Local.xcconfig. With an App Store Connect API key in
# ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH (e.g. in scripts/local.env) it also works without Xcode signed in.
# Release builds compile out the DEBUG hooks; you sign in on the device.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
UDID="$1"
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -project HolyArrs.xcodeproj -scheme HolyArrs -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/dev \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration "${AUTH[@]}" \
  build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
ROW="$(xcrun devicectl list devices 2>/dev/null | grep "$UDID" || true)"
if [[ "$ROW" == *TV* ]]; then
  APP=build/dev/Build/Products/Release-appletvos/HolyArrs.app
elif [[ "$ROW" == *iPhone* || "$ROW" == *iPad* ]]; then
  APP=build/dev/Build/Products/Release-iphoneos/HolyArrs.app
else
  APP=build/dev/Build/Products/Release-xros/HolyArrs.app
fi
echo "app: $APP"
[[ "${2:-}" == "--no-install" ]] && exit 0
xcrun devicectl device install app --device "$UDID" "$APP"
