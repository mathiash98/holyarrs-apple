#!/bin/bash
# Takes a screenshot per page. Usage: scripts/sim-shots.sh <visionos|tvos> <outdir> name:tab[:route[:search]] ...
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
P="$1"; OUT="$2"; shift 2
DEV="$(sim_udid "$P")"
mkdir -p "$OUT"
for spec in "$@"; do
  IFS=: read -r name tab route query <<<"$spec"
  scripts/sim-run.sh "$P" "$tab" "${route:-}" "${query:-}" >/dev/null
  sleep "${WAIT:-10}"
  xcrun simctl io "$DEV" screenshot "$OUT/$P-$name.png" >/dev/null 2>&1 && echo "$OUT/$P-$name.png"
done
