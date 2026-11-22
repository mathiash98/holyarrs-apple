# Shared helpers for the scripts. Loads scripts/local.env (git-ignored) when present.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$here/local.env" ]] && source "$here/local.env"

# Simulator UDID by platform (visionos|tvos), creating one if none exists.
sim_udid() {
  local runtime_key name
  case "$1" in
    visionos) runtime_key=xrOS; name="Apple Vision Pro" ;;
    tvos) runtime_key=tvOS; name="Apple TV" ;;
    ios) runtime_key=iOS; name="iPhone" ;;
  esac
  xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
cands=[x for rt,devs in d.items() if '$runtime_key' in rt for x in devs if x['name'].startswith('$name')]
cands.sort(key=lambda x: ('Pro' not in x['name'], 'Max' in x['name']))
if cands: print(cands[0]['udid'])
"
}

app_path() {
  case "$1" in
    visionos) echo build/dd/Build/Products/Debug-xrsimulator/HolyArrs.app ;;
    tvos) echo build/dd/Build/Products/Debug-appletvsimulator/HolyArrs.app ;;
    ios) echo build/dd/Build/Products/Debug-iphonesimulator/HolyArrs.app ;;
  esac
}
